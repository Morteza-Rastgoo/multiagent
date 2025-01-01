#!/bin/bash
set -e

# Create .ssh directory if it doesn't exist
mkdir -p ~/.ssh
chmod 700 ~/.ssh

# Generate SSH key if it doesn't exist
if [ ! -f ~/.ssh/id_rsa ]; then
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
fi

# Set correct permissions
chmod 600 ~/.ssh/id_rsa
chmod 644 ~/.ssh/id_rsa.pub

# Copy SSH key to remote server
ssh-copy-id -i ~/.ssh/id_rsa.pub mrastgo@10.251.165.183

# Test connection
ssh -o BatchMode=yes mrastgo@10.251.165.183 "echo 'SSH connection successful'" 