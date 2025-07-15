# Changelog

## [Enhanced Custom Repository Support] - 2024-12-19

### Added
- **Dynamic Project Directory Support**: The deployment script now dynamically sets the project directory based on the repository name instead of using a hardcoded path
- **Existing .env File Detection**: Script now checks for existing `.env` files in current directory and `/root` and moves them to the project directory
- **Dynamic Service Naming**: Systemd service names are now generated based on the repository name for better organization

### Changed
- **Repository Selection**: Enhanced repository selection to automatically configure project directories
- **Environment File Handling**: Improved .env file management with support for existing configurations
- **Project Structure**: Modified to support multiple AI workflow projects simultaneously

### Technical Improvements

#### Dynamic Directory Management
```bash
# Before (hardcoded)
PROJECT_DIR="/opt/self-hosted-ai-starter-kit"
SERVICE_NAME="n8n-ai"

# After (dynamic)
PROJECT_DIR=""  # Set based on repository name
SERVICE_NAME="" # Set based on repository name
```

#### Enhanced Repository Handling
- Added `set_project_directory()` function to extract repository name and configure paths
- Project directory now follows pattern: `/opt/<repository-name>`
- Service name follows pattern: `<repository-name>-service`

#### Improved .env File Management
- Detects existing `.env` files in current directory or `/root`
- Preserves existing configurations by moving them to project directory
- Falls back to template-based configuration if no existing file found
- Maintains proper file permissions (600) for security

### Benefits
1. **Multi-Project Support**: Deploy multiple AI workflow instances with different repositories
2. **Configuration Preservation**: Existing environment configurations are preserved during deployment
3. **Better Organization**: Each project gets its own directory and service name
4. **Flexible Deployment**: Works with any compatible repository, not just the default n8n starter kit

### Migration Notes
- Existing deployments using the default repository will continue to work
- New deployments will use dynamic naming based on repository
- Users with existing `.env` files can now deploy without losing their configuration

### Examples

#### Custom Repository Deployment
```bash
# User provides: https://github.com/myuser/my-ai-workflow.git
# Results in:
# - Project Directory: /opt/my-ai-workflow
# - Service Name: my-ai-workflow-service
# - Existing .env moved to /opt/my-ai-workflow/.env
```

#### Default Repository Deployment
```bash
# Default: https://github.com/n8n-io/self-hosted-ai-starter-kit.git
# Results in:
# - Project Directory: /opt/self-hosted-ai-starter-kit
# - Service Name: self-hosted-ai-starter-kit-service
```
