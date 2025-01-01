# Multi-Agent AI Voice Assistant

Create the bash script that sets up A voice-activated AI assistant that can control machines and respond in both English and Persian (Farsi). The system uses a distributed architecture with language models running on a remote server for better performance and resource management.

## Architecture

### Remote Server (mrastgo@10.251.165.183)
- Hosts Ollama server for language model inference
- Runs the large language models:
  - A smart online model for general conversations that can act like perplexity and connect to the internet and get the information online
  - a code very professional model for code generation
- Handles all heavy computational tasks
- Connected via SSH tunnel for secure communication

### Local Machine
- Handles voice recognition using Whisper
- Processes text-to-speech using local engines
- Manages user interaction and system control
- Connects to remote LLMs via secure SSH tunnel

## Features
- Voice activation in both English and Persian
- Local voice processing for low latency
- Remote model inference for better performance
- Secure communication via SSH
- Code generation and execution capabilities
- System control and automation
- Interactive conversation in both languages

## Technical Details
- Uses Whisper medium model for better Persian recognition
- Automatic language detection and response
- SSH tunnel for secure model access
- Local execution of system commands
- Optimized voice synthesis for both languages
- Fallback mechanisms for error handling

## Requirements
- SSH access to remote server
- Python 3.11+
- Local audio hardware
- Network connection

## Usage
1. Run `./install.sh` to set up both local and remote components
2. Execute `./run.sh` to start the assistant
3. Speak commands in either English or Persian
4. The assistant will respond in the same language

Note: All language model processing is done on the remote server, while voice processing remains local for better responsiveness.