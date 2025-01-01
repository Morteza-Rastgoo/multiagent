#!/bin/bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Test counter
total_tests=0
passed_tests=0

# Function to run a test
run_test() {
    local test_name=$1
    local command=$2
    total_tests=$((total_tests + 1))
    
    printf "${BLUE}[TEST ${total_tests}]${NC} ${BOLD}Testing: ${test_name}${NC}\n"
    if eval "$command" > /dev/null 2>&1; then
        printf "${GREEN}✓ Passed:${NC} ${test_name}\n"
        passed_tests=$((passed_tests + 1))
    else
        printf "${RED}✗ Failed:${NC} ${test_name}\n"
        printf "${YELLOW}ℹ Running diagnostic command:${NC}\n"
        eval "$command"
    fi
    echo
}

# Print header
printf "${BOLD}${BLUE}╔════════════════════════════════════════════╗${NC}\n"
printf "${BOLD}${BLUE}║${NC}    ${GREEN}Multi-Agent Integration Tests${NC}         ${BOLD}${BLUE}║${NC}\n"
printf "${BOLD}${BLUE}╚════════════════════════════════════════════╝${NC}\n\n"

# 1. Test Python environment
run_test "Python Virtual Environment" "source venv/bin/activate && python3 -c 'import sys; sys.exit(0 if sys.prefix != sys.base_prefix else 1)'"

# 2. Test Ollama Local Service
run_test "Local Ollama Service" "pgrep ollama"

# 3. Test SSH Connection
run_test "SSH Connection" "ssh -q mrastgo@10.251.165.183 exit"

# 4. Test SSH Tunnel
run_test "SSH Tunnel" "pgrep -f 'ssh -f -N -L 11434:localhost:11434'"

# 5. Test Remote Ollama Service
run_test "Remote Ollama Service" "ssh mrastgo@10.251.165.183 'pgrep ollama'"

# 6. Test Required Models
echo "Testing required models..."
models=("neural-chat:7b-v3.3-q4_K_M" "codellama:7b-instruct-q4_K_M" "mistral:7b-instruct-q4_K_M")
for model in "${models[@]}"; do
    run_test "Model: $model" "ssh mrastgo@10.251.165.183 'ollama list | grep -q \"$model\"'"
done

# 7. Test Python Packages
echo "Testing Python packages..."
packages=(
    "openai-whisper"
    "SpeechRecognition"
    "pyttsx3"
    "langchain"
    "torch"
    "transformers"
)
for package in "${packages[@]}"; do
    run_test "Package: $package" "source venv/bin/activate && python3 -c 'import $package'"
done

# 8. Test Whisper Model
run_test "Whisper Model" "test -f $HOME/.cache/whisper/medium.pt"

# 9. Test Audio Devices
run_test "Audio Devices" "source venv/bin/activate && python3 -c 'import sounddevice as sd; sd.query_devices()'"

# 10. Test Configuration
run_test "Configuration File" "test -f config/config.env && source config/config.env"

# Print summary
echo
printf "${BOLD}${BLUE}═══════════════ Test Summary ═══════════════${NC}\n"
printf "${BOLD}Tests Run:    ${NC}${total_tests}\n"
printf "${BOLD}${GREEN}Tests Passed: ${NC}${passed_tests}\n"
printf "${BOLD}${RED}Tests Failed: ${NC}$((total_tests - passed_tests))\n"

# Calculate percentage
percentage=$((passed_tests * 100 / total_tests))
printf "${BOLD}Success Rate: ${NC}${percentage}%%\n"

# Print final status
if [ $passed_tests -eq $total_tests ]; then
    printf "\n${GREEN}✓ All integration tests passed!${NC}\n"
else
    printf "\n${RED}✗ Some tests failed. Please check the output above for details.${NC}\n"
    exit 1
fi 