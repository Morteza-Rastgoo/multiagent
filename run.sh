#!/bin/bash
set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Function to print error messages
error() {
    echo -e "${RED}Error: $1${NC}" >&2
}

# Function to print success messages
success() {
    echo -e "${GREEN}$1${NC}"
}

# Function to print warning messages
warning() {
    echo -e "${YELLOW}Warning: $1${NC}"
}

# Function to cleanup on exit
cleanup() {
    echo "Cleaning up..."
    # Kill SSH tunnel by port number to ensure we get the right one
    if [[ -f .tunnel.pid ]]; then
        kill $(cat .tunnel.pid) 2>/dev/null || true
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
    if [ $attempt -ge $max_attempts ]; then
        error "Could not free port 11434 after $max_attempts attempts"
        exit 1
    fi
    warning "Port 11434 is still in use. Waiting for it to be available... (attempt $attempt/$max_attempts)"
    sleep 2
    attempt=$((attempt + 1))
done

# Set up new SSH tunnel with PID tracking
echo "Setting up SSH tunnel..."
ssh -f -N -L 11434:localhost:11434 mrastgo@10.251.165.183 & echo $! > .tunnel.pid

# Wait for tunnel to be established
attempt=1
while ! curl -s localhost:11434/api/tags >/dev/null 2>&1; do
    if [ $attempt -ge $max_attempts ]; then
        error "Could not establish SSH tunnel after $max_attempts attempts"
        exit 1
    fi
    warning "Waiting for SSH tunnel to be established... (attempt $attempt/$max_attempts)"
    sleep 2
    attempt=$((attempt + 1))
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
