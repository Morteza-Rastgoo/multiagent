#!/bin/bash
set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Function to check command status
check_status() {
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: $1 failed${NC}" >&2
        exit 1
    fi
}

# Function to show warning
show_warning() {
    echo -e "${YELLOW}⚠ Warning:${NC} $1"
}

# Function to show success
show_success() {
    echo -e "${GREEN}✓${NC} $1"
}

# Function to show info
show_info() {
    echo -e "${CYAN}ℹ${NC} $1"
}

# Function to show error
show_error() {
    echo -e "${RED}❌ Error:${NC} $1"
}

# Function to show header
show_header() {
    clear
    echo -e "${BOLD}${BLUE}╔════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${BLUE}║${NC}     ${GREEN}Multi-Agent Voice Assistant Setup${NC}     ${BOLD}${BLUE}║${NC}"
    echo -e "${BOLD}${BLUE}╚════════════════════════════════════════════╝${NC}\n"
}

# Check if pv is installed
if ! command -v pv &> /dev/null; then
    show_info "Installing pv for progress display..."
    if [[ "$(uname)" == "Darwin" ]]; then
        brew install pv
    else
        sudo apt-get update && sudo apt-get install -y pv
    fi
fi

# Show header
show_header

# Initialize progress tracking
total_steps=15
current_step=0

# Function to update progress
show_progress() {
    current_step=$((current_step + 1))
    echo "$current_step" | pv -l -s $total_steps -N "$1" > /dev/null
}

# Check if running on Apple Silicon
show_progress "Checking system compatibility"
if [ "$(uname -m)" != "arm64" ]; then
    show_warning "This script is optimized for Apple Silicon (M1/M2) Macs."
    show_warning "Some features may not work as expected on your system."
fi

# Install Homebrew if not installed
show_progress "Setting up Homebrew"
if ! command -v brew &> /dev/null; then
    show_info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    check_status "Homebrew installation"
fi

# Install system dependencies
show_progress "Installing system dependencies"
if command -v ollama &> /dev/null; then
    show_info "Ollama is already installed locally"
    current_version=$(ollama --version 2>&1 | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" || echo "0.0.0")
    show_info "Current Ollama version: $current_version"
    show_info "Updating other dependencies..."
    brew install portaudio python@3.11 ffmpeg sox
else
    show_info "Installing Ollama and other dependencies..."
    brew install portaudio python@3.11 ollama ffmpeg sox
fi
check_status "System dependencies installation"

# Ensure local Ollama service is running
show_progress "Starting Ollama service"
if ! pgrep ollama > /dev/null; then
    show_info "Starting local Ollama service..."
    ollama serve &
    sleep 5
else
    show_info "Local Ollama service is already running"
fi

# Set up SSH key for remote server
show_progress "Setting up SSH keys"
mkdir -p ~/.ssh
chmod 700 ~/.ssh
if [ ! -f ~/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
fi
chmod 600 ~/.ssh/id_rsa
chmod 644 ~/.ssh/id_rsa.pub

# Copy SSH key to remote server
show_info "Copying SSH key to remote server..."
ssh-copy-id -i ~/.ssh/id_rsa.pub mrastgo@10.251.165.183
check_status "SSH key setup"

# Install Ollama on remote server
show_progress "Setting up remote Ollama"
show_info "Checking Ollama installation on remote server..."
ssh mrastgo@10.251.165.183 '
    if command -v ollama &> /dev/null; then
        echo "Ollama is already installed"
        current_version=$(ollama --version 2>&1 | grep -oE "[0-9]+\.[0-9]+\.[0-9]+" || echo "0.0.0")
        echo "Current Ollama version: $current_version"
    else
        echo "Installing Ollama..."
        curl https://ollama.ai/install.sh | sh
    fi

    # Ensure Ollama service is running
    if ! pgrep ollama > /dev/null; then
        echo "Starting Ollama service..."
        ollama serve &
        sleep 5
    else
        echo "Ollama service is already running"
    fi
'
check_status "Remote Ollama setup"

# Pull required models on remote server
show_progress "Installing language models"
show_info "Installing language models on remote server..."
ssh mrastgo@10.251.165.183 '
    # Function to check if model is installed
    check_model() {
        ollama list | grep -q "^$1"
        return $?
    }

    # Function to pull model with retry
    pull_model() {
        local model=$1
        local max_attempts=3
        local attempt=1
        
        if check_model "$model"; then
            echo "Model $model is already installed"
            return 0
        fi
        
        echo "Model $model not found, installing..."
        while [ $attempt -le $max_attempts ]; do
            echo "Pulling $model (attempt $attempt/$max_attempts)..."
            if ollama pull $model; then
                echo "$model successfully pulled"
                return 0
            fi
            attempt=$((attempt + 1))
            sleep 5
        done
        echo "Failed to pull $model after $max_attempts attempts"
        return 1
    }

    # Pull each required model
    models=(
        "neural-chat:7b-v3.3-q4_K_M"
        "codellama:7b-instruct-q4_K_M"
        "mistral:7b-instruct-q4_K_M"
        "llama2:7b-chat-q4_K_M"
    )

    echo "Current installed models:"
    ollama list

    echo "Checking and installing required models..."
    for model in "${models[@]}"; do
        if ! pull_model "$model"; then
            echo "Error: Failed to install $model"
            exit 1
        fi
    done

    echo "All models successfully installed:"
    ollama list
'
check_status "Model installation"

# Create Python virtual environment
show_progress "Setting up Python environment"
show_info "Creating Python virtual environment..."
if [ ! -d "venv" ]; then
    python3 -m venv venv
    check_status "Virtual environment creation"
else
    show_info "Virtual environment already exists"
fi

source venv/bin/activate

# Install Python packages
show_progress "Installing Python packages"

# Set up SSL certificates for pip
export REQUESTS_CA_BUNDLE="$(python3 -c 'import certifi; print(certifi.where())')"
export SSL_CERT_FILE="$(python3 -c 'import certifi; print(certifi.where())')"
export CURL_CA_BUNDLE="$(python3 -c 'import certifi; print(certifi.where())')"

# First install certifi with compatible version
show_info "Installing certifi..."
pip install --no-cache-dir "certifi>=2023.7.22,<2024.0.0"

# Install core dependencies first
show_info "Installing core dependencies..."
pip install --no-cache-dir \
    openai==0.28.1 \
    requests==2.31.0 \
    python-dotenv==1.0.0 \
    pydantic==1.10.13

# Install audio packages
show_info "Installing audio packages..."
pip install --no-cache-dir \
    sounddevice==0.4.6 \
    numpy==1.26.2 \
    pyaudio==0.2.14 \
    pyttsx3==2.90 \
    SpeechRecognition==3.10.0 \
    playsound==1.3.0 \
    gtts==2.4.0

# Install ML packages
show_info "Installing ML packages..."
pip install --no-cache-dir \
    torch==2.1.2 \
    torchaudio==2.1.2 \
    transformers==4.36.1 \
    openai-whisper==20231117

# Install LangChain packages
show_info "Installing LangChain packages..."
pip install --no-cache-dir \
    langchain==0.0.350 \
    langchain-community==0.0.13 \
    langchain-experimental==0.0.47

# Install open-interpreter and its dependencies
show_info "Installing open-interpreter and dependencies..."
pip install --no-cache-dir "litellm>=0.13.2,<0.14.0"
pip install --no-cache-dir "open-interpreter>=0.1.17,<0.2.0"

# Verify installations with proper package names
show_info "Verifying package installations..."
python3 -c "
import openai
import langchain
import whisper
import sounddevice
import pydantic
import interpreter
print('All required packages verified successfully')
" || {
    show_error "Package verification failed"
    show_info "Attempting to fix package installation..."
    
    # Try reinstalling open-interpreter with specific version
    pip install --no-cache-dir --force-reinstall open-interpreter==0.1.17
    
    # Verify again
    python3 -c "
    import openai
    import langchain
    import whisper
    import sounddevice
    import pydantic
    import interpreter
    print('Package verification successful after fix')
    " || {
        show_error "Package verification still failed after fix attempt"
        exit 1
    }
}

check_status "Python packages installation"

# Download Whisper model
show_progress "Setting up Whisper model"
show_info "Checking Whisper model..."
if [ -d "$HOME/.cache/whisper/medium.pt" ]; then
    show_info "Whisper medium model is already downloaded"
else
    show_info "Downloading Whisper model..."
    # Create a temporary Python script to handle SSL certificate issues
    cat > download_whisper.py << EOL
import os
import ssl
import whisper
import certifi
import urllib.request

# Create SSL context with verified certificates
ssl_context = ssl.create_default_context(cafile=certifi.where())

# Create a custom opener with our SSL context
opener = urllib.request.build_opener(urllib.request.HTTPSHandler(context=ssl_context))
urllib.request.install_opener(opener)

try:
    print("Downloading Whisper medium model...")
    model = whisper.load_model('medium')
    print("Whisper model downloaded successfully")
except Exception as e:
    print(f"Error downloading model: {str(e)}")
    exit(1)
EOL

    # Run the temporary Python script
    PYTHONPATH="${PYTHONPATH}:${PWD}/venv/lib/python3.11/site-packages" \
    REQUESTS_CA_BUNDLE="$(python3 -c 'import certifi; print(certifi.where())')" \
    SSL_CERT_FILE="$(python3 -c 'import certifi; print(certifi.where())')" \
    python3 download_whisper.py
    check_status "Whisper model download"
    
    # Clean up temporary script
    rm download_whisper.py
fi

# Create config directory
show_progress "Creating configuration files"
show_info "Creating config directory..."
mkdir -p config

# Create config.env file
show_info "Creating config.env file..."
cat > config/config.env << EOL
WHISPER_MODEL="medium"
LANGUAGE_SUPPORT='["en-US", "fa-IR"]'
LLM_MODEL="neural-chat:7b-v3.3-q4_K_M"
CODING_MODEL="codellama:7b-instruct-q4_K_M"
CHAT_MODEL="mistral:7b-instruct-q4_K_M"
TEMPERATURE=0.7
MAX_TOKENS=2048
CONTEXT_LENGTH=4096
MEMORY_SIZE=10
TTS_PROVIDER="elevenlabs"
VOICE_ID="persian_male"
CONVERSATION_STYLE="creative"
ENABLE_INTERPRETER=true
ENABLE_CODE_EXECUTION=true
ENABLE_VOICE_FEEDBACK=true
REMOTE_HOST="10.251.165.183"
REMOTE_USER="mrastgo"
INTERPRETER_LOCAL=false
MODEL_CONFIG='{
    "mistral": {
        "model": "mistral:7b-instruct-q4_K_M",
        "temperature": 0.7,
        "max_tokens": 2048,
        "system_prompt": "You are a helpful AI assistant that can understand and respond in both English and Persian."
    },
    "codellama": {
        "model": "codellama:7b-instruct-q4_K_M",
        "temperature": 0.5,
        "max_tokens": 4096,
        "system_prompt": "You are an expert programmer. Provide detailed and well-documented code solutions."
    },
    "neural-chat": {
        "model": "neural-chat:7b-v3.3-q4_K_M",
        "temperature": 0.7,
        "max_tokens": 2048,
        "system_prompt": "You are a friendly AI assistant that can engage in natural conversations in both English and Persian."
    }
}'
OLLAMA_CONFIG='{
    "host": "localhost",
    "port": 11434,
    "timeout": 120
}'
EOL
check_status "Configuration file creation"

# Create run.sh script
show_progress "Creating startup script"
show_info "Creating run.sh script..."
cat > run.sh << EOL
#!/bin/bash
set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to print error messages
error() {
    echo -e "\${RED}Error: \$1\${NC}" >&2
}

# Function to print success messages
success() {
    echo -e "\${GREEN}\$1\${NC}"
}

# Function to print warning messages
warning() {
    echo -e "\${YELLOW}Warning: \$1\${NC}"
}

# Function to cleanup on exit
cleanup() {
    echo "Cleaning up..."
    # Kill SSH tunnel by port number to ensure we get the right one
    if [[ -f .tunnel.pid ]]; then
        kill \$(cat .tunnel.pid) 2>/dev/null || true
        rm .tunnel.pid
    fi
    # Kill any processes using our port
    lsof -ti:11434 | xargs kill -9 2>/dev/null || true
}

trap cleanup EXIT INT TERM

# Check if virtual environment exists
if [ ! -d "venv" ]; then
    error "Virtual environment not found. Please run install.sh first"
    exit 1
fi

# Check if config exists
if [ ! -f "config/config.env" ]; then
    error "Configuration file not found. Please run install.sh first"
    exit 1
fi

# Check if main.py exists
if [ ! -f "main.py" ]; then
    error "main.py not found. Please ensure all files are in place"
    exit 1
fi

# Check if we can connect to the remote server
if ! ssh -q mrastgo@10.251.165.183 exit 2>/dev/null; then
    error "Cannot connect to remote server. Please check your SSH configuration"
    exit 1
fi

# Disable SSL verification for Python
export PYTHONHTTPSVERIFY=0
export REQUESTS_CA_BUNDLE=""

# Kill any existing SSH tunnels and processes using our port
cleanup

# Wait for port to be available
max_attempts=5
attempt=1
while lsof -i:11434 >/dev/null 2>&1; do
    if [ \$attempt -ge \$max_attempts ]; then
        error "Could not free port 11434 after \$max_attempts attempts"
        exit 1
    fi
    warning "Port 11434 is still in use. Waiting for it to be available... (attempt \$attempt/\$max_attempts)"
    sleep 2
    attempt=\$((attempt + 1))
done

# Set up new SSH tunnel with PID tracking
echo "Setting up SSH tunnel..."
ssh -f -N -L 11434:localhost:11434 mrastgo@10.251.165.183 & echo \$! > .tunnel.pid

# Wait for tunnel to be established
attempt=1
while ! curl -s localhost:11434/api/tags >/dev/null 2>&1; do
    if [ \$attempt -ge \$max_attempts ]; then
        error "Could not establish SSH tunnel after \$max_attempts attempts"
        exit 1
    fi
    warning "Waiting for SSH tunnel to be established... (attempt \$attempt/\$max_attempts)"
    sleep 2
    attempt=\$((attempt + 1))
done
success "SSH tunnel established successfully"

# Source environment variables
set -a
source config/config.env
set +a

# Activate virtual environment
source venv/bin/activate

# Verify Python environment
echo "Verifying Python environment..."
if ! python3 -c "import speech_recognition, gtts, playsound, langchain" 2>/dev/null; then
    error "Required Python packages are not properly installed"
    exit 1
fi
success "Python environment verified"

# Check audio devices
echo "Checking audio devices..."
if ! python3 -c "import speech_recognition as sr; sr.Microphone()" 2>/dev/null; then
    warning "No microphone detected. Speech recognition may not work"
else
    success "Audio devices detected"
fi

# Run the assistant
success "Starting AI assistant..."
python3 main.py
EOL

chmod +x run.sh

# Final verification
show_progress "Running final checks"
show_info "Verifying installation..."

# Check SSH connection
show_info "Testing SSH connection..."
if ! ssh -q mrastgo@10.251.165.183 exit; then
    show_error "SSH connection failed"
    exit 1
fi
show_success "SSH connection successful"

# Check Ollama availability
show_info "Testing Ollama service..."
if ! curl -s localhost:11434/api/tags > /dev/null; then
    show_error "Cannot connect to Ollama service"
    exit 1
fi
show_success "Ollama service responding"

# Test Python environment
show_info "Testing Python environment..."
if ! python3 -c "import whisper, langchain, openai" 2>/dev/null; then
    show_error "Required Python packages not properly installed"
    exit 1
fi
show_success "Python environment configured correctly"

# Test audio devices
show_info "Testing audio devices..."
if ! python3 -c "import sounddevice as sd; sd.query_devices()" >/dev/null 2>&1; then
    show_warning "Audio devices might not be properly configured"
else
    show_success "Audio devices detected"
fi

# Final success message
show_progress "Installation complete"
show_success "Installation completed successfully!"
show_info "You can now run the assistant with ${BOLD}./run.sh${NC}" 