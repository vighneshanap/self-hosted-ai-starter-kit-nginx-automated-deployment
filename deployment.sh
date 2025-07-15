#!/bin/bash

# N8N Self-Hosted AI Starter Kit Setup Script for Multiple Linux Distributions
# Author: AI Engineering Team
# Description: Multi-distro automated setup script with error handling and user prompts
# Supported: Ubuntu, Debian, CentOS, RHEL, Fedora, Amazon Linux 2, SUSE/openSUSE

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
DOMAIN=""
EMAIL=""
GITLAB_REPO=""
PROJECT_DIR=""  # Will be set based on repository name
NGINX_CONFIG_FILE=""
SERVICE_NAME=""
GPU_PROFILE="cpu"

# Distribution variables
DISTRO=""
DISTRO_VERSION=""
PACKAGE_MANAGER=""
INSTALL_CMD=""
UPDATE_CMD=""
FIREWALL_CMD=""

# Logging functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Function to ask yes/no questions
ask_yes_no() {
    local question="$1"
    local default="${2:-n}"
    local answer
    
    while true; do
        if [[ "$default" == "y" ]]; then
            read -p "$question [Y/n]: " answer
            answer=${answer:-y}
        else
            read -p "$question [y/N]: " answer
            answer=${answer:-n}
        fi
        
        case ${answer,,} in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) echo "Please answer yes or no." ;;
        esac
    done
}

# Function to extract repository name and set project directory
set_project_directory() {
    local repo_url="$1"
    local repo_name
    
    # Extract repository name from URL
    # Handle various formats: https://github.com/user/repo.git, https://github.com/user/repo, etc.
    repo_name=$(basename "$repo_url" .git)
    
    # Set project directory and service name based on repository name
    PROJECT_DIR="/opt/$repo_name"
    SERVICE_NAME="$repo_name-service"
    
    log "Project directory set to: $PROJECT_DIR"
    log "Service name set to: $SERVICE_NAME"
}

# Function to detect Linux distribution
detect_distro() {
    log "Detecting Linux distribution..."
    
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        DISTRO=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
        DISTRO_VERSION="$VERSION_ID"
    elif [[ -f /etc/redhat-release ]]; then
        DISTRO="rhel"
        DISTRO_VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release | head -1)
    elif [[ -f /etc/debian_version ]]; then
        DISTRO="debian"
        DISTRO_VERSION=$(cat /etc/debian_version)
    else
        error "Cannot detect Linux distribution"
        exit 1
    fi
    
    # Handle distribution variants
    case "$DISTRO" in
        "ubuntu"|"debian")
            PACKAGE_MANAGER="apt"
            INSTALL_CMD="apt-get install -y"
            UPDATE_CMD="apt-get update"  # Fixed: removed && command
            FIREWALL_CMD="ufw"
            ;;
        "centos"|"rhel"|"rocky"|"almalinux")
            PACKAGE_MANAGER="yum"
            if command -v dnf &> /dev/null; then
                PACKAGE_MANAGER="dnf"
                INSTALL_CMD="dnf install -y"
                UPDATE_CMD="dnf update -y"
            else
                INSTALL_CMD="yum install -y"
                UPDATE_CMD="yum update -y"
            fi
            FIREWALL_CMD="firewalld"
            ;;
        "fedora")
            PACKAGE_MANAGER="dnf"
            INSTALL_CMD="dnf install -y"
            UPDATE_CMD="dnf update -y"
            FIREWALL_CMD="firewalld"
            ;;
        "amzn")
            PACKAGE_MANAGER="yum"
            INSTALL_CMD="yum install -y"
            UPDATE_CMD="yum update -y"
            FIREWALL_CMD="firewalld"
            DISTRO="amazon"
            ;;
        "sles"|"opensuse"|"opensuse-leap"|"opensuse-tumbleweed")
            PACKAGE_MANAGER="zypper"
            INSTALL_CMD="zypper install -y"
            UPDATE_CMD="zypper update -y"
            FIREWALL_CMD="firewalld"
            DISTRO="suse"
            ;;
        *)
            error "Unsupported distribution: $DISTRO"
            info "Supported distributions: Ubuntu, Debian, CentOS, RHEL, Fedora, Amazon Linux 2, SUSE/openSUSE"
            exit 1
            ;;
    esac
    
    log "Detected: $DISTRO $DISTRO_VERSION"
    log "Package Manager: $PACKAGE_MANAGER"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        error "This script should not be run as root. Please run as a regular user with sudo privileges."
        exit 1
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if user has sudo privileges
    if ! sudo -n true 2>/dev/null; then
        error "User does not have sudo privileges"
        exit 1
    fi
    
    # Check internet connectivity
    if ! ping -c 1 google.com &> /dev/null; then
        error "No internet connectivity detected"
        exit 1
    fi
    
    # Check if git is installed, install if not
    if ! command -v git &> /dev/null; then
        warning "Git not found. Installing..."
        sudo $INSTALL_CMD git
    fi
    
    # Check if curl is installed, install if not
    if ! command -v curl &> /dev/null; then
        warning "Curl not found. Installing..."
        sudo $INSTALL_CMD curl
    fi
    
    log "Prerequisites check passed"
}

# Function to collect user input
collect_user_input() {
    log "Collecting configuration details..."
    
    echo ""
    info "N8N will be configured for a subdomain of your main domain."
    info "Choose a subdomain that clearly identifies this as your AI/automation platform."
    echo ""
    info "Suggested subdomain names:"
    info "  • ai.yourcompany.com (AI/automation platform)"
    info "  • n8n.yourcompany.com (direct n8n reference)"
    info "  • automation.yourcompany.com (workflow automation)"
    info "  • workflows.yourcompany.com (business workflows)"
    info "  • integration.yourcompany.com (system integrations)"
    echo ""
    
    while [[ -z "$DOMAIN" ]]; do
        read -p "Enter your SUBDOMAIN for N8N (e.g., ai.yourcompany.com): " DOMAIN
        
        # Check if it's a valid subdomain format (subdomain.domain.tld)
        if [[ ! "$DOMAIN" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)+$ ]]; then
            error "Invalid domain format. Please try again."
            error "Domain should contain only letters, numbers, dots, and hyphens"
            DOMAIN=""
        elif [[ $(echo "$DOMAIN" | tr '.' '\n' | wc -l) -lt 3 ]]; then
            warning "You entered: $DOMAIN"
            warning "This appears to be a root domain (domain.tld). N8N should typically use a subdomain."
            warning "Examples: ai.yourcompany.com, n8n.demo.ai, automation.company.io"
            if ask_yes_no "Continue with '$DOMAIN' anyway?"; then
                break
            else
                DOMAIN=""
            fi
        elif [[ "$DOMAIN" =~ \.\. ]] || [[ "$DOMAIN" =~ ^\.|\.$|^-|-$ ]]; then
            error "Invalid domain format. Cannot have consecutive dots or start/end with dots/hyphens."
            DOMAIN=""
        else
            log "Subdomain '$DOMAIN' looks good!"
            break
        fi
    done
    
    while [[ -z "$EMAIL" ]]; do
        read -p "Enter your email for SSL certificate: " EMAIL
        if [[ ! "$EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            error "Invalid email format. Please try again."
            EMAIL=""
        fi
    done
    
    echo ""
    info "Repository Configuration:"
    info "Default: https://github.com/n8n-io/self-hosted-ai-starter-kit.git (official n8n AI starter kit)"
    echo ""
    
    if ask_yes_no "Use the default n8n AI starter kit repository?" "y"; then
        GITLAB_REPO="https://github.com/n8n-io/self-hosted-ai-starter-kit.git"
        log "Using official n8n AI starter kit repository"
    else
        while [[ -z "$GITLAB_REPO" ]]; do
            read -p "Enter your custom repository URL: " GITLAB_REPO
            if [[ ! "$GITLAB_REPO" =~ ^https?:// ]]; then
                error "Invalid repository URL. Please include http:// or https://"
                GITLAB_REPO=""
            fi
        done
    fi
    
    # Set project directory based on repository name
    set_project_directory "$GITLAB_REPO"
    
    echo ""
    info "GPU/Hardware Configuration:"
    info "N8N AI starter kit supports different hardware profiles for optimal performance:"
    echo ""
    info "Available options:"
    info "  1. CPU Only (default) - Works on all systems, slower AI processing"
    info "  2. NVIDIA GPU - Best performance for AI workloads, requires NVIDIA GPU + drivers"
    info "  3. AMD GPU (Linux) - Good performance for AI workloads, requires AMD GPU + ROCm"
    echo ""
    
    while true; do
        read -p "Select hardware profile [1-CPU/2-NVIDIA/3-AMD] (default: 1): " gpu_choice
        gpu_choice=${gpu_choice:-1}
        
        case $gpu_choice in
            1|cpu|CPU)
                GPU_PROFILE="cpu"
                log "Selected: CPU Only profile"
                break
                ;;
            2|nvidia|NVIDIA)
                GPU_PROFILE="gpu-nvidia"
                warning "NVIDIA GPU profile selected"
                info "Requirements:"
                info "  - NVIDIA GPU installed"
                info "  - NVIDIA drivers installed"
                info "  - NVIDIA Container Toolkit installed"
                info "  - Docker configured for GPU access"
                echo ""
                if ask_yes_no "Do you have NVIDIA GPU properly configured with Docker?" "n"; then
                    log "Selected: NVIDIA GPU profile"
                    break
                else
                    warning "Please configure NVIDIA GPU with Docker first, or choose CPU profile"
                    info "See: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html"
                fi
                ;;
            3|amd|AMD)
                GPU_PROFILE="gpu-amd"
                warning "AMD GPU profile selected (Linux only)"
                info "Requirements:"
                info "  - AMD GPU installed"
                info "  - ROCm drivers installed"
                info "  - Docker configured for ROCm access"
                echo ""
                if ask_yes_no "Do you have AMD GPU properly configured with ROCm and Docker?" "n"; then
                    log "Selected: AMD GPU profile"
                    break
                else
                    warning "Please configure AMD GPU with ROCm first, or choose CPU profile"
                    info "See: https://rocmdocs.amd.com/en/latest/deploy/docker.html"
                fi
                ;;
            *)
                error "Invalid selection. Please choose 1, 2, or 3."
                ;;
        esac
    done
    
    NGINX_CONFIG_FILE="/etc/nginx/sites-available/$(echo $DOMAIN | cut -d'.' -f1)"
    
    echo ""
    log "Configuration collected:"
    info "N8N Subdomain: $DOMAIN"
    info "SSL Email: $EMAIL"
    info "Repository: $GITLAB_REPO"
    info "Hardware Profile: $GPU_PROFILE"
    info "Nginx config: $NGINX_CONFIG_FILE"
    echo ""
    warning "IMPORTANT: Make sure your DNS A record for '$DOMAIN' points to this server's IP address"
    warning "before proceeding with SSL setup, otherwise certificate generation will fail."
    echo ""
    if ask_yes_no "Continue with this configuration?" "y"; then
        log "Proceeding with installation..."
    else
        error "Configuration cancelled by user"
        exit 1
    fi
}

# Function to update system
update_system() {
    if ask_yes_no "Update system packages?"; then
        log "Updating system packages..."
        
        case "$DISTRO" in
            "ubuntu"|"debian")
                sudo apt-get update && sudo apt-get upgrade -y || {
                    error "Failed to update system packages"
                    exit 1
                }
                ;;
            "centos"|"rhel"|"rocky"|"almalinux"|"amazon"|"fedora")
                sudo $UPDATE_CMD || {
                    error "Failed to update system packages"
                    exit 1
                }
                ;;
            "suse")
                sudo $UPDATE_CMD || {
                    error "Failed to update system packages"
                    exit 1
                }
                ;;
            *)
                # Fallback to the UPDATE_CMD variable
                sudo $UPDATE_CMD || {
                    error "Failed to update system packages"
                    exit 1
                }
                ;;
        esac
        
        log "System updated successfully"
    else
        info "Skipping system update"
    fi
}

# Function to install Docker (distribution-specific)
install_docker() {
    if ask_yes_no "Install Docker and Docker Compose?"; then
        log "Installing Docker for $DISTRO..."
        
        case "$DISTRO" in
            "ubuntu"|"debian")
                install_docker_debian_ubuntu
                ;;
            "centos"|"rhel"|"rocky"|"almalinux"|"amazon"|"fedora")
                install_docker_rhel_centos
                ;;
            "suse")
                install_docker_suse
                ;;
        esac
        
        # Add user to docker group
        sudo usermod -aG docker $USER
        
        log "Docker installed successfully"
    else
        info "Skipping Docker installation"
    fi
}

# Docker installation for Debian/Ubuntu
install_docker_debian_ubuntu() {
    # Remove old versions
    sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Install dependencies
    sudo $INSTALL_CMD \
        ca-certificates \
        curl \
        gnupg \
        lsb-release || {
        error "Failed to install Docker dependencies"
        exit 1
    }
    
    # Add Docker GPG key
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/$DISTRO/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    
    # Add Docker repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$DISTRO $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker
    sudo apt-get update
    sudo $INSTALL_CMD docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

# Docker installation for RHEL/CentOS/Fedora/Amazon Linux
install_docker_rhel_centos() {
    # Remove old versions
    sudo $PACKAGE_MANAGER remove -y docker docker-client docker-client-latest docker-common docker-latest docker-latest-logrotate docker-logrotate docker-engine 2>/dev/null || true
    
    # Install dependencies
    if [[ "$DISTRO" == "amazon" ]]; then
        sudo $INSTALL_CMD docker
        sudo systemctl start docker
        sudo systemctl enable docker
        
        # Install docker-compose separately for Amazon Linux
        sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        sudo chmod +x /usr/local/bin/docker-compose
    else
        # For CentOS/RHEL/Fedora
        sudo $INSTALL_CMD dnf-plugins-core || sudo $INSTALL_CMD yum-utils
        
        # Add Docker repository
        if [[ "$DISTRO" == "fedora" ]]; then
            sudo $PACKAGE_MANAGER config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
        else
            sudo $PACKAGE_MANAGER config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        fi
        
        # Install Docker
        sudo $INSTALL_CMD docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        sudo systemctl start docker
        sudo systemctl enable docker
    fi
}

# Docker installation for SUSE
install_docker_suse() {
    # Remove old versions
    sudo zypper remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Add Docker repository
    sudo zypper addrepo https://download.docker.com/linux/sles/docker-ce.repo
    sudo zypper refresh
    
    # Install Docker
    sudo $INSTALL_CMD docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    sudo systemctl start docker
    sudo systemctl enable docker
}

# Function to install Nginx (distribution-specific)
install_nginx() {
    if ask_yes_no "Install and configure Nginx?"; then
        log "Installing Nginx for $DISTRO..."
        
        case "$DISTRO" in
            "ubuntu"|"debian")
                sudo $INSTALL_CMD nginx
                ;;
            "centos"|"rhel"|"rocky"|"almalinux"|"fedora")
                sudo $INSTALL_CMD nginx
                ;;
            "amazon")
                sudo amazon-linux-extras install nginx1 -y || sudo $INSTALL_CMD nginx
                ;;
            "suse")
                sudo $INSTALL_CMD nginx
                ;;
        esac
        
        # Create sites-available and sites-enabled directories if they don't exist (for non-Debian systems)
        sudo mkdir -p /etc/nginx/sites-available
        sudo mkdir -p /etc/nginx/sites-enabled
        
        # Add include statement to nginx.conf if not present
        if ! grep -q "sites-enabled" /etc/nginx/nginx.conf; then
            sudo sed -i '/http {/a\    include /etc/nginx/sites-enabled/*;' /etc/nginx/nginx.conf
        fi
        
        sudo systemctl start nginx
        sudo systemctl enable nginx || {
            error "Failed to start/enable Nginx"
            exit 1
        }
        
        log "Nginx installed and started successfully"
    else
        info "Skipping Nginx installation"
        warning "You'll need to configure your own reverse proxy for N8N"
        warning "N8N will run on http://localhost:5678"
        info "Make sure to proxy requests to port 5678 and handle SSL termination"
    fi
}

# Function to install Certbot (distribution-specific)
install_certbot() {
    if ask_yes_no "Install Certbot for SSL certificates?"; then
        log "Installing Certbot for $DISTRO..."
        
        case "$DISTRO" in
            "ubuntu"|"debian")
                sudo $INSTALL_CMD certbot python3-certbot-nginx
                ;;
            "centos"|"rhel"|"rocky"|"almalinux")
                # Enable EPEL repository first
                sudo $INSTALL_CMD epel-release
                sudo $INSTALL_CMD certbot python3-certbot-nginx
                ;;
            "fedora")
                sudo $INSTALL_CMD certbot python3-certbot-nginx
                ;;
            "amazon")
                sudo amazon-linux-extras install epel -y
                sudo $INSTALL_CMD certbot python3-certbot-nginx
                ;;
            "suse")
                sudo $INSTALL_CMD certbot python3-certbot-nginx
                ;;
        esac
        
        log "Certbot installed successfully"
    else
        info "Skipping Certbot installation"
    fi
}

# Function to collect environment variables
collect_env_variables() {
    log "Collecting N8N environment configuration..."
    
    # Basic Authentication
    echo ""
    info "N8N Basic Authentication Setup:"
    info "This will secure your N8N instance with username/password"
    echo ""
    
    local n8n_auth_user=""
    local n8n_auth_password=""
    local postgres_user="root"
    local postgres_password=""
    local postgres_db="n8n"
    local n8n_encryption_key=""
    local n8n_jwt_secret=""
    
    while [[ -z "$n8n_auth_user" ]]; do
        read -p "Enter N8N admin username (email format recommended): " n8n_auth_user
        if [[ ! "$n8n_auth_user" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            warning "Email format recommended for username (e.g., admin@yourcompany.com)"
            if ! ask_yes_no "Continue with '$n8n_auth_user' anyway?"; then
                n8n_auth_user=""
            fi
        fi
    done
    
    while [[ -z "$n8n_auth_password" ]]; do
        read -s -p "Enter N8N admin password (min 8 characters): " n8n_auth_password
        echo ""
        if [[ ${#n8n_auth_password} -lt 8 ]]; then
            error "Password must be at least 8 characters long"
            n8n_auth_password=""
        fi
    done
    
    # Database Configuration
    echo ""
    info "Database Configuration:"
    
    read -p "PostgreSQL username (default: $postgres_user): " input_postgres_user
    postgres_user=${input_postgres_user:-$postgres_user}
    
    while [[ -z "$postgres_password" ]]; do
        read -s -p "Enter PostgreSQL password (min 8 characters): " postgres_password
        echo ""
        if [[ ${#postgres_password} -lt 8 ]]; then
            error "Database password must be at least 8 characters long"
            postgres_password=""
        fi
    done
    
    read -p "PostgreSQL database name (default: $postgres_db): " input_postgres_db
    postgres_db=${input_postgres_db:-$postgres_db}
    
    # Encryption Keys
    echo ""
    info "Security Keys Configuration:"
    echo ""
    
    info "N8N requires a 32-character encryption key for securing data."
    info "Generate one using: openssl rand -hex 16"
    echo ""
    
    if ask_yes_no "Generate encryption key automatically?" "y"; then
        if command -v openssl &> /dev/null; then
            n8n_encryption_key=$(openssl rand -hex 16)
            log "Generated 32-character encryption key"
        else
            warning "OpenSSL not found. Please enter manually."
        fi
    fi
    
    while [[ -z "$n8n_encryption_key" ]]; do
        read -p "Enter 32-character encryption key: " n8n_encryption_key
        if [[ ${#n8n_encryption_key} -ne 32 ]]; then
            error "Encryption key must be exactly 32 characters"
            info "Generate one with: openssl rand -hex 16"
            n8n_encryption_key=""
        fi
    done
    
    echo ""
    info "JWT secret for user management tokens."
    info "Generate one using: openssl rand -base64 32"
    echo ""
    
    if ask_yes_no "Generate JWT secret automatically?" "y"; then
        if command -v openssl &> /dev/null; then
            n8n_jwt_secret=$(openssl rand -base64 32)
            log "Generated JWT secret"
        else
            warning "OpenSSL not found. Please enter manually."
        fi
    fi
    
    while [[ -z "$n8n_jwt_secret" ]]; do
        read -p "Enter JWT secret (recommended 32+ characters): " n8n_jwt_secret
        if [[ ${#n8n_jwt_secret} -lt 16 ]]; then
            error "JWT secret should be at least 16 characters"
            info "Generate one with: openssl rand -base64 32"
            n8n_jwt_secret=""
        fi
    done
    
    # Store in global variables for use in .env setup
    export N8N_AUTH_USER="$n8n_auth_user"
    export N8N_AUTH_PASSWORD="$n8n_auth_password"
    export POSTGRES_USER="$postgres_user"
    export POSTGRES_PASSWORD="$postgres_password"
    export POSTGRES_DB="$postgres_db"
    export N8N_ENCRYPTION_KEY="$n8n_encryption_key"
    export N8N_JWT_SECRET="$n8n_jwt_secret"
    
    echo ""
    log "Environment configuration collected successfully"
}

# Function to clone repository
clone_repository() {
    if ask_yes_no "Clone the AI starter kit repository?"; then
        log "Cloning repository..."
        
        # Remove existing directory if it exists
        if [[ -d "$PROJECT_DIR" ]]; then
            warning "Directory $PROJECT_DIR already exists. Removing..."
            sudo rm -rf "$PROJECT_DIR"
        fi
        
        # Clone repository
        sudo git clone "$GITLAB_REPO" "$PROJECT_DIR" || {
            error "Failed to clone repository"
            exit 1
        }
        
        # Change ownership
        sudo chown -R $USER:$USER "$PROJECT_DIR" || {
            error "Failed to change ownership"
            exit 1
        }
        
        # Collect environment variables
        collect_env_variables
        
        # Setup environment file
        EXISTING_ENV=""
        ENV_SOURCE=""
        
        # Check for existing .env file
        if [[ -f ".env" ]]; then
            log "Found existing .env file in current directory"
            EXISTING_ENV="$(pwd)/.env"
            ENV_SOURCE="current directory"
        elif [[ -f "/root/.env" ]]; then
            log "Found existing .env file in /root"
            EXISTING_ENV="/root/.env"
            ENV_SOURCE="/root"
        fi
        
        if [[ ! -f "$PROJECT_DIR/.env" ]]; then
            if [[ -n "$EXISTING_ENV" ]]; then
                log "Moving existing .env file from $ENV_SOURCE to $PROJECT_DIR/"
                cp "$EXISTING_ENV" "$PROJECT_DIR/.env" || {
                    error "Failed to move existing .env file"
                    exit 1
                }
                chmod 600 "$PROJECT_DIR/.env"
                log "Existing .env file successfully moved and configured"
                echo ""
                info "Using existing environment configuration from $ENV_SOURCE"
                warning "Backup this file securely: $PROJECT_DIR/.env"
                
            elif [[ -f "$PROJECT_DIR/.env.example" ]]; then
                log "Setting up environment configuration from template..."
                cp "$PROJECT_DIR/.env.example" "$PROJECT_DIR/.env" || {
                    error "Failed to copy .env.example to .env"
                    exit 1
                }
                
                # Update .env with collected configuration
                log "Configuring environment variables..."
                
                # Domain settings
                sed -i "s|DOMAIN=.*|DOMAIN=$DOMAIN|g" "$PROJECT_DIR/.env" 2>/dev/null || true
                
                # n8n Configuration
                sed -i "s|N8N_PROTOCOL=.*|N8N_PROTOCOL=https|g" "$PROJECT_DIR/.env" 2>/dev/null || true
                sed -i "s|N8N_HOST=.*|N8N_HOST=$DOMAIN|g" "$PROJECT_DIR/.env" 2>/dev/null || true
                sed -i "s|WEBHOOK_URL=.*|WEBHOOK_URL=https://$DOMAIN|g" "$PROJECT_DIR/.env" 2>/dev/null || true
                sed -i "s|WEBHOOK_TUNNEL_URL=.*|WEBHOOK_TUNNEL_URL=https://$DOMAIN|g" "$PROJECT_DIR/.env" 2>/dev/null || true
                
                # n8n authentication
                sed -i "s|N8N_BASIC_AUTH_ACTIVE=.*|N8N_BASIC_AUTH_ACTIVE=true|g" "$PROJECT_DIR/.env" 2>/dev/null || true
                sed -i "s|N8N_BASIC_AUTH_USER=.*|N8N_BASIC_AUTH_USER=$N8N_AUTH_USER|g" "$PROJECT_DIR/.env" 2>/dev/null || true
                sed -i "s|N8N_BASIC_AUTH_PASSWORD=.*|N8N_BASIC_AUTH_PASSWORD=$N8N_AUTH_PASSWORD|g" "$PROJECT_DIR/.env" 2>/dev/null || true
                
                # Database settings
                sed -i "s|POSTGRES_USER=.*|POSTGRES_USER=$POSTGRES_USER|g" "$PROJECT_DIR/.env" 2>/dev/null || true
                sed -i "s|POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$POSTGRES_PASSWORD|g" "$PROJECT_DIR/.env" 2>/dev/null || true
                sed -i "s|POSTGRES_DB=.*|POSTGRES_DB=$POSTGRES_DB|g" "$PROJECT_DIR/.env" 2>/dev/null || true
                
                # n8n encryption and security
                sed -i "s|N8N_ENCRYPTION_KEY=.*|N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY|g" "$PROJECT_DIR/.env" 2>/dev/null || true
                sed -i "s|N8N_USER_MANAGEMENT_JWT_SECRET=.*|N8N_USER_MANAGEMENT_JWT_SECRET=$N8N_JWT_SECRET|g" "$PROJECT_DIR/.env" 2>/dev/null || true
                
                # If variables don't exist in .env, append them
                if ! grep -q "DOMAIN=" "$PROJECT_DIR/.env"; then
                    echo "" >> "$PROJECT_DIR/.env"
                    echo "# Domain settings" >> "$PROJECT_DIR/.env"
                    echo "DOMAIN=$DOMAIN" >> "$PROJECT_DIR/.env"
                fi
                
                if ! grep -q "N8N_BASIC_AUTH_ACTIVE=" "$PROJECT_DIR/.env"; then
                    echo "" >> "$PROJECT_DIR/.env"
                    echo "# n8n authentication" >> "$PROJECT_DIR/.env"
                    echo "N8N_BASIC_AUTH_ACTIVE=true" >> "$PROJECT_DIR/.env"
                    echo "N8N_BASIC_AUTH_USER=$N8N_AUTH_USER" >> "$PROJECT_DIR/.env"
                    echo "N8N_BASIC_AUTH_PASSWORD=$N8N_AUTH_PASSWORD" >> "$PROJECT_DIR/.env"
                fi
                
                if ! grep -q "POSTGRES_USER=" "$PROJECT_DIR/.env"; then
                    echo "" >> "$PROJECT_DIR/.env"
                    echo "# Database settings" >> "$PROJECT_DIR/.env"
                    echo "POSTGRES_USER=$POSTGRES_USER" >> "$PROJECT_DIR/.env"
                    echo "POSTGRES_PASSWORD=$POSTGRES_PASSWORD" >> "$PROJECT_DIR/.env"
                    echo "POSTGRES_DB=$POSTGRES_DB" >> "$PROJECT_DIR/.env"
                fi
                
                if ! grep -q "N8N_ENCRYPTION_KEY=" "$PROJECT_DIR/.env"; then
                    echo "" >> "$PROJECT_DIR/.env"
                    echo "# n8n encryption and security" >> "$PROJECT_DIR/.env"
                    echo "N8N_ENCRYPTION_KEY=$N8N_ENCRYPTION_KEY" >> "$PROJECT_DIR/.env"
                    echo "N8N_USER_MANAGEMENT_JWT_SECRET=$N8N_JWT_SECRET" >> "$PROJECT_DIR/.env"
                fi
                
                # Set proper permissions for .env file
                chmod 600 "$PROJECT_DIR/.env"
                
                log "Environment file configured successfully"
                echo ""
                info "Configuration Summary:"
                info "  Domain: $DOMAIN"
                info "  N8N Admin User: $N8N_AUTH_USER"
                info "  Database: $POSTGRES_DB (user: $POSTGRES_USER)"
                info "  Security: Encryption key and JWT secret configured"
                echo ""
                warning "IMPORTANT: Your .env file contains sensitive information."
                warning "File permissions set to 600 (owner read/write only)"
                warning "Backup this file securely: $PROJECT_DIR/.env"
                
            else
                warning ".env.example not found in repository"
                warning "You'll need to create .env file manually"
            fi
        else
            log ".env file already exists in project directory - skipping configuration"
        fi
        
        log "Repository cloned and configured successfully"
    else
        info "Skipping repository clone"
    fi
}

# Function to create Nginx configuration
create_nginx_config() {
    # Check if nginx is installed
    if ! command -v nginx &> /dev/null; then
        warning "Nginx not installed. Skipping Nginx configuration."
        info "If you install Nginx later, you can create the config manually"
        return 0
    fi
    
    if ask_yes_no "Create Nginx configuration for $DOMAIN?"; then
        log "Creating Nginx configuration..."
        
        sudo tee "$NGINX_CONFIG_FILE" > /dev/null <<EOF
server {
    server_name $DOMAIN;

    # Allow Let's Encrypt challenges
    location /.well-known/acme-challenge/ {
        root /var/www/html;
        try_files \$uri \$uri/ =404;
    }

    location / {
        proxy_pass http://localhost:5678;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header X-Forwarded-Host \$host;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_connect_timeout 30s;
        proxy_send_timeout 30s;
        proxy_read_timeout 30s;
        
        # Additional security headers
        proxy_set_header X-Frame-Options DENY;
        proxy_set_header X-Content-Type-Options nosniff;
        proxy_set_header X-XSS-Protection "1; mode=block";
    }

    location /health {
        access_log off;
        return 200 "healthy\\n";
        add_header Content-Type text/plain;
    }

    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;

    listen 80;
}
EOF
        
        # Enable the site
        sudo ln -sf "$NGINX_CONFIG_FILE" "/etc/nginx/sites-enabled/$(basename $NGINX_CONFIG_FILE)" || {
            error "Failed to enable Nginx site"
            exit 1
        }
        
        # Remove default site
        sudo rm -f /etc/nginx/sites-enabled/default
        
        # Test configuration
        sudo nginx -t || {
            error "Nginx configuration test failed"
            exit 1
        }
        
        # Reload Nginx
        sudo systemctl reload nginx || {
            error "Failed to reload Nginx"
            exit 1
        }
        
        log "Nginx configuration created and activated"
    else
        info "Skipping Nginx configuration"
        info "You'll need to configure your reverse proxy manually"
    fi
}

# Function to create N8N systemd service
create_n8n_service() {
    if ask_yes_no "Create systemd service for N8N?"; then
        log "Creating N8N systemd service with $GPU_PROFILE profile..."
        
        # Determine docker-compose command
        local compose_cmd="docker-compose"
        if command -v docker &> /dev/null && docker compose version &> /dev/null; then
            compose_cmd="docker compose"
        fi
        
        # Build the profile command
        local profile_cmd="--profile $GPU_PROFILE"
        
        log "Using Docker Compose profile: $GPU_PROFILE"
        if [[ "$GPU_PROFILE" == "gpu-nvidia" ]]; then
            info "NVIDIA GPU profile will be used - ensure GPU drivers and container toolkit are installed"
        elif [[ "$GPU_PROFILE" == "gpu-amd" ]]; then
            info "AMD GPU profile will be used - ensure ROCm drivers are installed"
        else
            info "CPU profile will be used - works on all systems"
        fi
        
        sudo tee "/etc/systemd/system/${SERVICE_NAME}.service" > /dev/null <<EOF
[Unit]
Description=N8N AI Workflow Automation ($GPU_PROFILE)
Documentation=https://docs.n8n.io
After=network.target docker.service
Requires=docker.service

[Service]
Type=forking
User=$USER
Group=docker
WorkingDirectory=$PROJECT_DIR
Environment=NODE_ENV=production
Environment=N8N_HOST=$DOMAIN
Environment=N8N_PORT=5678
Environment=N8N_PROTOCOL=https
Environment=WEBHOOK_URL=https://$DOMAIN/
Environment=GENERIC_TIMEZONE=UTC
ExecStartPre=/bin/bash -c 'cd $PROJECT_DIR && $compose_cmd pull'
ExecStart=/bin/bash -c 'cd $PROJECT_DIR && $compose_cmd $profile_cmd up -d'
ExecStop=/bin/bash -c 'cd $PROJECT_DIR && $compose_cmd $profile_cmd down'
ExecReload=/bin/bash -c 'cd $PROJECT_DIR && $compose_cmd $profile_cmd restart'
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=n8n-ai

[Install]
WantedBy=multi-user.target
EOF

        # Reload systemd
        sudo systemctl daemon-reload || {
            error "Failed to reload systemd"
            exit 1
        }
        
        # Enable service
        sudo systemctl enable "${SERVICE_NAME}" || {
            error "Failed to enable N8N service"
            exit 1
        }
        
        log "N8N systemd service created and enabled with $GPU_PROFILE profile"
        
        if [[ "$GPU_PROFILE" != "cpu" ]]; then
            echo ""
            warning "GPU Profile Notes:"
            if [[ "$GPU_PROFILE" == "gpu-nvidia" ]]; then
                info "  - Verify NVIDIA drivers: nvidia-smi"
                info "  - Verify container toolkit: docker run --rm --gpus all nvidia/cuda:11.0-base nvidia-smi"
                info "  - Documentation: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/"
            elif [[ "$GPU_PROFILE" == "gpu-amd" ]]; then
                info "  - Verify ROCm: rocm-smi"
                info "  - Verify Docker ROCm: docker run --rm --device=/dev/kfd --device=/dev/dri rocm/tensorflow:latest rocm-smi"
                info "  - Documentation: https://rocmdocs.amd.com/en/latest/"
            fi
            echo ""
        fi
        
    else
        info "Skipping N8N service creation"
    fi
}

# Function to setup SSL
setup_ssl() {
    # Check if nginx is installed
    if ! command -v nginx &> /dev/null; then
        warning "Nginx not installed. Skipping SSL setup."
        info "SSL certificates require a web server for domain validation."
        info "Install nginx or another web server first, then run:"
        info "  sudo certbot --nginx -d $DOMAIN --email $EMAIL"
        return 0
    fi
    
    if ask_yes_no "Setup SSL certificate with Let's Encrypt?"; then
        log "Setting up SSL certificate..."
        
        # Run certbot
        if sudo certbot --nginx -d "$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive; then
            log "SSL certificate setup completed successfully"
            
            # Test auto-renewal
            if sudo certbot renew --dry-run; then
                log "SSL auto-renewal test passed"
            else
                warning "SSL auto-renewal test failed, but certificate is installed"
            fi
        else
            error "Failed to setup SSL certificate"
            echo ""
            warning "Common SSL setup issues:"
            info "  1. Domain DNS not pointing to this server's IP"
            info "  2. Domain not yet propagated (wait 24-48 hours)"
            info "  3. Let's Encrypt rate limits (try again later)"
            info "  4. Firewall blocking port 80/443"
            info "  5. Another service using port 80"
            echo ""
            warning "Check the following log files for detailed errors:"
            info "  - Certbot logs: /var/log/letsencrypt/letsencrypt.log"
            info "  - Nginx error logs: /var/log/nginx/error.log"
            echo ""
            info "You can manually setup SSL later with:"
            info "  sudo certbot --nginx -d $DOMAIN --email $EMAIL"
            echo ""
            
            if ask_yes_no "Skip SSL setup and continue with the installation?" "y"; then
                warning "Continuing without SSL - your site will be HTTP only"
                info "You can setup SSL manually after the installation completes"
            else
                error "Stopping installation. Please fix SSL issues and run the script again."
                exit 1
            fi
        fi
    else
        info "Skipping SSL setup"
    fi
}

# Function to configure firewall (distribution-specific)
configure_firewall() {
    if ask_yes_no "Configure firewall?"; then
        log "Configuring firewall for $DISTRO..."
        
        case "$FIREWALL_CMD" in
            "ufw")
                configure_ufw_firewall
                ;;
            "firewalld")
                configure_firewalld_firewall
                ;;
        esac
        
        log "Firewall configured successfully"
    else
        info "Skipping firewall configuration"
    fi
}

# Configure UFW firewall (Ubuntu/Debian)
configure_ufw_firewall() {
    # Install UFW if not installed
    sudo $INSTALL_CMD ufw
    
    # Configure firewall rules
    sudo ufw --force reset
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    sudo ufw allow ssh
    
    if command -v nginx &> /dev/null; then
        sudo ufw allow 'Nginx Full'
        log "Configured firewall for Nginx"
    else
        warning "Nginx not installed - you'll need to configure firewall for your reverse proxy"
        info "For example: sudo ufw allow 80 && sudo ufw allow 443"
    fi
    
    sudo ufw --force enable
}

# Configure firewalld (RHEL/CentOS/Fedora/SUSE)
configure_firewalld_firewall() {
    # Install firewalld if not installed
    sudo $INSTALL_CMD firewalld
    
    # Start and enable firewalld
    sudo systemctl start firewalld
    sudo systemctl enable firewalld
    
    # Configure firewall rules
    sudo firewall-cmd --permanent --add-service=ssh
    
    if command -v nginx &> /dev/null; then
        sudo firewall-cmd --permanent --add-service=http
        sudo firewall-cmd --permanent --add-service=https
        log "Configured firewall for Nginx (HTTP/HTTPS)"
    else
        warning "Nginx not installed - you'll need to configure firewall for your reverse proxy"
        info "For example: sudo firewall-cmd --permanent --add-port=80/tcp --add-port=443/tcp"
    fi
    
    sudo firewall-cmd --reload
}

# Function to start services
start_services() {
    if ask_yes_no "Start N8N service?"; then
        log "Starting N8N service..."
        
        # Ensure user is in docker group (requires re-login)
        if ! groups $USER | grep -q docker; then
            warning "User $USER is not in docker group. You may need to log out and log back in."
            if ask_yes_no "Add user to docker group and continue?"; then
                sudo usermod -aG docker $USER
                # Use newgrp to apply group changes in current session
                newgrp docker <<EOF
sudo systemctl start "${SERVICE_NAME}" || {
    error "Failed to start N8N service"
    exit 1
}
EOF
            fi
        else
            sudo systemctl start "${SERVICE_NAME}" || {
                error "Failed to start N8N service"
                exit 1
            }
        fi
        
        # Wait for service to start
        sleep 15
        
        log "N8N service started"
    else
        info "Skipping service start"
    fi
}

# Function to verify installation
verify_installation() {
    log "Running verification checks..."
    
    local all_good=true
    
    # Check OS and version
    log "✓ Operating System: $DISTRO $DISTRO_VERSION"
    log "✓ Package Manager: $PACKAGE_MANAGER"
    
    # Check Nginx status (if installed)
    if command -v nginx &> /dev/null; then
        if sudo systemctl is-active --quiet nginx; then
            log "✓ Nginx is running"
        else
            error "✗ Nginx is not running"
            all_good=false
        fi
    else
        warning "Nginx not installed - using external reverse proxy"
    fi
    
    # Check N8N service status
    if sudo systemctl is-active --quiet "${SERVICE_NAME}"; then
        log "✓ N8N service is running"
    else
        error "✗ N8N service is not running"
        all_good=false
    fi
    
    # Check if port 5678 is listening
    if command -v netstat &> /dev/null; then
        if sudo netstat -tlnp | grep -q ":5678"; then
            log "✓ N8N is listening on port 5678"
        else
            error "✗ N8N is not listening on port 5678"
            all_good=false
        fi
    elif command -v ss &> /dev/null; then
        if sudo ss -tlnp | grep -q ":5678"; then
            log "✓ N8N is listening on port 5678"
        else
            error "✗ N8N is not listening on port 5678"
            all_good=false
        fi
    fi
    
    # Check HTTP response
    if curl -s -o /dev/null -w "%{http_code}" "http://localhost:5678" | grep -q "200\|302"; then
        log "✓ N8N is responding on localhost"
    else
        error "✗ N8N is not responding on localhost"
        all_good=false
    fi
    
    # Check HTTPS if SSL was setup
    if [[ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]]; then
        if curl -s -o /dev/null -w "%{http_code}" "https://$DOMAIN" | grep -q "200\|302"; then
            log "✓ HTTPS is working for $DOMAIN"
        else
            error "✗ HTTPS is not working for $DOMAIN"
            all_good=false
        fi
        
        # Check SSL certificate details
        log "✓ SSL certificate exists"
        local cert_expiry=$(sudo openssl x509 -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" -noout -enddate | cut -d= -f2)
        log "  Certificate expires: $cert_expiry"
    else
        warning "SSL certificate not found - site running on HTTP only"
        info "  You can setup SSL manually later with: sudo certbot --nginx -d $DOMAIN"
        
        # Check HTTP access instead
        if curl -s -o /dev/null -w "%{http_code}" "http://$DOMAIN" | grep -q "200\|302"; then
            log "✓ HTTP is working for $DOMAIN"
        else
            error "✗ HTTP is not working for $DOMAIN"
            all_good=false
        fi
    fi
    
    # Docker status
    if docker --version &>/dev/null; then
        log "✓ Docker is installed ($(docker --version | cut -d' ' -f3 | tr -d ','))"
        if docker ps &>/dev/null; then
            log "✓ Docker is accessible"
        else
            error "✗ Docker is not accessible (may need to re-login)"
            all_good=false
        fi
    else
        error "✗ Docker is not installed"
        all_good=false
    fi
    
    # Firewall status
    case "$FIREWALL_CMD" in
        "ufw")
            if sudo ufw status | grep -q "Status: active"; then
                log "✓ UFW firewall is active"
            else
                warning "UFW firewall is not active"
            fi
            ;;
        "firewalld")
            if sudo systemctl is-active --quiet firewalld; then
                log "✓ Firewalld is active"
            else
                warning "Firewalld is not active"
            fi
            ;;
    esac
    
    echo ""
    if [[ "$all_good" == true ]]; then
        log "🎉 Installation completed successfully!"
        info "You can access N8N at: https://$DOMAIN"
        info "Service status: sudo systemctl status $SERVICE_NAME"
        info "Service logs: sudo journalctl -u $SERVICE_NAME -f"
    else
        error "❌ Some components failed verification"
        warning "Check the errors above and run individual commands to troubleshoot"
    fi
    
    echo ""
    info "System Information:"
    info "  OS: $DISTRO $DISTRO_VERSION"
    info "  Package Manager: $PACKAGE_MANAGER"
    info "  Firewall: $FIREWALL_CMD"
    info "  Hardware Profile: $GPU_PROFILE"
    
    echo ""
    info "Useful commands:"
    info "  Check N8N logs: sudo journalctl -u $SERVICE_NAME -f"
    info "  Restart N8N: sudo systemctl restart $SERVICE_NAME"
    if command -v nginx &> /dev/null; then
        info "  Check Nginx: sudo systemctl status nginx"
    fi
    info "  Test SSL renewal: sudo certbot renew --dry-run"
    info "  Edit environment: nano $PROJECT_DIR/.env"
    info "  View current config: cat $PROJECT_DIR/.env | grep -v PASSWORD | grep -v SECRET"
    info "  Generate new encryption key: openssl rand -hex 16"
    info "  Generate new JWT secret: openssl rand -base64 32"
    
    case "$FIREWALL_CMD" in
        "ufw")
            info "  Check firewall: sudo ufw status"
            if ! command -v nginx &> /dev/null; then
                info "  Note: Without nginx, you may need to configure firewall for your reverse proxy"
            fi
            ;;
        "firewalld")
            info "  Check firewall: sudo firewall-cmd --list-all"
            if ! command -v nginx &> /dev/null; then
                info "  Note: Without nginx, you may need to configure firewall for your reverse proxy"
            fi
            ;;
    esac
}

# Function to cleanup on error
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "Script failed with exit code $exit_code"
        warning "Check the logs above for details"
    fi
}

# Main function
main() {
    trap cleanup EXIT
    
    echo ""
    log "=== N8N Self-Hosted AI Starter Kit Setup Script ==="
    log "=== Multi-Distribution Support ==="
    echo ""
    
    check_root
    detect_distro
    check_prerequisites
    collect_user_input
    
    echo ""
    log "Starting installation process for $DISTRO $DISTRO_VERSION..."
    echo ""
    
    update_system
    install_docker
    install_nginx
    install_certbot
    clone_repository
    create_nginx_config
    create_n8n_service
    setup_ssl
    configure_firewall
    start_services
    
    echo ""
    verify_installation
    
    echo ""
    log "Setup process completed!"
    
    if ask_yes_no "Show final service status?"; then
        echo ""
        if command -v nginx &> /dev/null; then
            sudo systemctl status nginx --no-pager
            echo ""
        fi
        sudo systemctl status "${SERVICE_NAME}" --no-pager
    fi
}

# Run main function
main "$@"