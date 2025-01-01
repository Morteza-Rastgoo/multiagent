#!/bin/bash

# Check if SSH key exists
SSH_KEY="$HOME/.ssh/id_ed25519"
if [ ! -f "$SSH_KEY" ]; then
    echo "SSH key not found. Creating new SSH key..."
    # Generate SSH key
    ssh-keygen -t ed25519 -C "$(git config --global user.email)" -f "$SSH_KEY" -N ""
    
    # Start ssh-agent and add key
    eval "$(ssh-agent -s)"
    ssh-add "$SSH_KEY"
    
    # Display public key and instructions
    echo -e "\nYour SSH public key is:\n"
    cat "${SSH_KEY}.pub"
    echo -e "\nPlease add this SSH key to your GitHub account:"
    echo "1. Go to GitHub → Settings → SSH and GPG keys"
    echo "2. Click 'New SSH key'"
    echo "3. Paste the above key and save"
    echo -e "\nPress Enter after adding the key to GitHub..."
    read -r
fi

# Test SSH connection to GitHub
echo "Testing GitHub SSH connection..."
if ! ssh -T git@github.com 2>&1 | grep -q "success"; then
    echo "Error: SSH authentication to GitHub failed"
    echo "Please make sure you've added your SSH key to GitHub"
    exit 1
fi

# Initialize git if not already initialized
if [ ! -d .git ]; then
    echo "Initializing git repository..."
    git init
fi

# Configure git if needed
if [ -z "$(git config --global user.email)" ]; then
    echo "Please enter your git email:"
    read git_email
    git config --global user.email "$git_email"
fi

if [ -z "$(git config --global user.name)" ]; then
    echo "Please enter your git username:"
    read git_username
    git config --global user.name "$git_username"
fi

# Get GitHub username
GITHUB_USERNAME=$(git config --global user.name)
if [ -z "$GITHUB_USERNAME" ]; then
    echo "Please enter your GitHub username:"
    read GITHUB_USERNAME
fi

# Create repository using GitHub CLI if installed, otherwise provide manual instructions
if command -v gh &> /dev/null; then
    echo "Creating repository using GitHub CLI..."
    gh repo create multiagent --public --description "A voice-activated AI assistant with multi-model capabilities" || true
else
    echo "Please create a repository named 'multiagent' on GitHub if it doesn't exist:"
    echo "1. Go to https://github.com/new"
    echo "2. Repository name: multiagent"
    echo "3. Description: A voice-activated AI assistant with multi-model capabilities"
    echo "4. Choose 'Public'"
    echo "5. Click 'Create repository'"
    echo -e "\nPress Enter after creating the repository..."
    read -r
fi

# Add remote if not already added
if ! git remote | grep -q '^origin$'; then
    echo "Adding remote origin..."
    git remote add origin "git@github.com:$GITHUB_USERNAME/multiagent.git"
fi

# Stage changes
echo "Staging changes..."
git add .

# Commit changes
echo "Committing changes..."
commit_message="Initial commit: Voice-activated AI Assistant

- Multi-model support (chat, code, speech)
- Bilingual capabilities (English, Persian)
- Remote model inference
- Local voice processing
- Enhanced error handling
- Secure configuration
- Progress tracking
- Code generation capabilities"

git commit -m "$commit_message"

# Push changes
echo "Pushing to GitHub..."
git push -u origin main

echo "Setup complete! Repository is available at: https://github.com/$GITHUB_USERNAME/multiagent" 