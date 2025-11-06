# LiteLLM Gateway with OAuth2 + JWT Authentication

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Docker](https://img.shields.io/badge/Docker-Compose-2496ED?logo=docker)](https://www.docker.com/)
[![Auth0](https://img.shields.io/badge/Auth-Auth0-EB5424?logo=auth0)](https://auth0.com/)

> Enterprise-grade LLM API Gateway with OAuth2 authentication and JWT token management, built for secure team collaboration.

[日本語版 README はこちら](README-ja.md)

---

## 🌟 Features

- **🔐 Dual Authentication**
  - OAuth2 (Auth0) for browser-based access
  - JWT tokens for API/CLI clients (up to 90 days validity)

- **🛡️ Enhanced Security**
  - Immediate token revocation on user removal
  - Redis-based token blacklist management
  - **Session deletion with re-login prevention** (NEW)
  - OAuth2 session check (planned: daily re-authentication)

- **📊 Complete Observability**
  - Real-time tracing with Langfuse
  - Per-user usage analytics (OAuth2 email attached to all API requests)
  - Cost tracking by model/user
  - Individual user budget limits available

- **🔄 Token & Session Management**
  - Web-based token administration UI
  - **Web-based session management UI** (NEW)
  - Multiple tokens per user
  - Custom expiration settings
  - **Force logout with deletion flag system** (NEW)

- **🚀 Production Ready**
  - Docker Compose deployment
  - OpenResty + LiteLLM architecture
  - PostgreSQL, Redis, ClickHouse integration

---

## 🏗️ Architecture

```
┌─────────────┐
│   Client    │ (Browser/Roo Code/CLI)
│  (User)     │
└──────┬──────┘
       │ OAuth2 / JWT
       ↓
┌──────────────────────────────────────┐
│         OpenResty (Gateway)          │
│  - JWT Validation                    │
│  - OAuth2 Session Check              │
│  - Session Deletion Flag Check (NEW) │
│  - Request Routing                   │
└──────┬───────────┬───────────────────┘
       │           │
       │           └──────────┐
       │                      ↓
       │                ┌──────────┐
       │                │  Redis   │
       │                │ (Tokens  │
       │                │  Sessions│
       │                │  Flags)  │
       │                └──────────┘
       │
    ┌──┴─────────────────┐
    │                    │
    ↓                    ↓
┌──────────────┐    ┌──────────────┐
│ OAuth2 Proxy │    │   LiteLLM    │
│   (Auth0)    │    │    Proxy     │
└──────────────┘    └──────┬───────┘
                           │
                    ┌──────┴─────┐
                    ↓            ↓
              ┌──────────┐  ┌──────────┐
              │ Langfuse │  │ Claude   │
              │(Tracing) │  │   API    │
              └──────────┘  └──────────┘
```

---

## 📋 Prerequisites

- Docker & Docker Compose v2
- Auth0 account (free tier available)
- Anthropic API key
- Ubuntu 24.04 or similar Linux distribution

---

## 🚀 Quick Start

### 1. Clone the Repository

```bash
git clone https://github.com/nakacya/llm-gateway-oauth.git
cd llm-gateway-oauth
```

### 2. Configure Environment Variables

```bash
# Copy sample configuration
cp .env_sample .env
cp oauth2_proxy.cfg.sample oauth2_proxy.cfg
cp litellm_config.yaml.sample litellm_config.yaml

# Edit with your credentials
vi .env
vi oauth2_proxy.cfg
vi litellm_config.yaml
```

**Required settings in `.env`**:
```bash
# Auth0 Configuration
AUTH0_DOMAIN=your-tenant.auth0.com
AUTH0_CLIENT_ID=your_client_id
AUTH0_CLIENT_SECRET=your_client_secret

# JWT Secret (generate with: openssl rand -base64 64)
JWT_SECRET=your_generated_secret

# Cookie Secret (see .env_sample for generation command)
OAUTH2_PROXY_COOKIE_SECRET=your_cookie_secret

# API Keys
ANTHROPIC_API_KEY=sk-ant-your-api-key
```

### 3. Set Up Auth0

1. Create an application in Auth0 Dashboard
2. Set Application Type: **Regular Web Application**
3. Configure URLs:
   - **Allowed Callback URLs**: `http://{your-fqdn}/oauth2/callback`
   - **Allowed Logout URLs**: `http://{your-fqdn}`
   - **Allowed Web Origins**: `http://{your-fqdn}`

Replace `{your-fqdn}` with your actual domain (e.g., `localhost`, `litellm.example.com`)

### 4. Build Custom OpenResty Image

```bash
# Build OpenResty with required modules
sudo docker compose build openresty

# This will:
# - Install lua-resty-jwt
# - Configure Lua modules
# - Set up custom OpenResty environment
```

### 5. Start Services

```bash
# Start all containers
sudo docker compose up -d

# Verify all containers are running
sudo docker compose ps
```

### 6. Verify Installation

```bash
# Check all containers are running
sudo docker compose ps

# Access the gateway
open http://{your-fqdn}

# Or use curl
curl -I http://{your-fqdn}
```

---

## 📖 Usage

### Browser Access

1. Navigate to `http://{your-fqdn}`
2. Log in via Auth0
3. Access Token Manager at `http://{your-fqdn}/token-manager`
4. Generate and manage JWT tokens through the web UI

**Available UIs**:
- **Token Manager** (`/token-manager`): Generate and manage your API tokens
- **Token & Session Manager** (`/token-session-manager`): Unified token and session management (admin only)
- **Admin Manager** (`/admin-manager`): Admin panel for user management (admin only)

### Generate JWT Token via Token Manager UI

1. Open `http://{your-fqdn}/token-manager` in your browser
2. Enter token name and expiration period
3. Click "Generate Token"
4. Copy the generated JWT token for API access

### Generate JWT Token via API

```bash
curl -X POST http://{your-fqdn}/api/token/generate \
  -H "Cookie: _oauth2_proxy=YOUR_COOKIE" \
  -H "Content-Type: application/json" \
  -d '{
    "token_name": "My API Token",
    "expires_in": 2592000
  }'
```

### API Call with JWT

```bash
curl -X POST http://{your-fqdn}/v1/messages \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "claude-sonnet-4-20250514",
    "max_tokens": 100,
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

### Roo Code Configuration

Configure in VS Code settings:

```json
{
  "rooCode.api.endpoint": "http://{your-fqdn}/v1",
  "rooCode.api.key": "your_jwt_token_here",
  "rooCode.model": "claude-sonnet-4-20250514"
}
```

Replace `{your-fqdn}` with your actual domain.

---

## 🔧 Configuration

### Supported Models

Add models in `litellm_config.yaml`:

```yaml
model_list:
  - model_name: claude-sonnet-4
    litellm_params:
      model: anthropic/claude-sonnet-4-20250514
      api_key: os.environ/ANTHROPIC_API_KEY

  - model_name: claude-haiku-4-5
    litellm_params:
      model: anthropic/claude-haiku-4-5-20251001
      api_key: os.environ/ANTHROPIC_API_KEY
```

### JWT Token Expiration

Default: 30 days (2,592,000 seconds)
Maximum: 90 days (7,776,000 seconds)

Modify in `lua/token_generator.lua`:

```lua
local MAX_EXPIRES_IN = 7776000  -- 90 days
```

### OAuth2 Session Timeout

Default: 24 hours

Modify in `oauth2_proxy.cfg`:

```ini
cookie_expire = "24h"
```

### LiteLLM Shared API Key Setup (Required)

After installation, you must create a **Shared API Key** (Virtual Key) in LiteLLM:

#### Step 1: Access LiteLLM Admin UI

```
http://{your-fqdn}:4000
```

Login with your master key (set in `.env` as `LITELLM_MASTER_KEY`)

#### Step 2: Create Virtual Key

1. Navigate to **"Keys"** tab
2. Click **"+ Create Key"**
3. Configure the key:
   - **Key Name**: `shared-api-key`
   - **Max Budget**: Set total budget for ALL users combined
   - **Duration**: Set budget reset period (e.g., `30d`)
4. Click **"Create Key"**
5. Copy the generated key (starts with `sk-...`)

#### Step 3: Update .env

```bash
# Add to .env
LITELLM_SHARED_KEY=sk-xxxxxxxxxxxxxxxx  # Your generated virtual key
```

#### Step 4: Restart Services

```bash
sudo docker compose restart
```

**Important Notes**:
- ⚠️ **All users share this single API key**
- ⚠️ **Budget limit applies to total usage across ALL users**
- ⚠️ **Multiple shared keys are not supported**
- ✅ Individual user usage is tracked via OAuth2 email in logs
- ✅ Per-user budget limits available (see below)

### Per-User Budget Limits (Optional)

LiteLLM supports individual user budget limits using the End User feature:

**Important**: LiteLLM automatically creates a Customer record when a user first makes an API request (via OAuth2 email). You can then update their budget settings.

#### Create New Customer with Budget (API)

For users who haven't made any requests yet:

```bash
curl -X POST 'http://{your-fqdn}:4000/customer/new' \
  -H 'Authorization: Bearer YOUR_MASTER_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "user_id": "user@example.com",
    "max_budget": 10.0,
    "budget_duration": "30d"
  }'
```

**Note**: If you get an error `"Customer already exists"`, this means the user has already made a request. Use the update endpoint below.

#### Update Existing Customer Budget (API)

For users who have already made requests:

```bash
curl -X POST 'http://{your-fqdn}:4000/customer/update' \
  -H 'Authorization: Bearer YOUR_MASTER_KEY' \
  -H 'Content-Type: application/json' \
  -d '{
    "user_id": "sample@example.com",
    "max_budget": 10.0,
    "budget_duration": "30d"
  }'
```

#### Check User Usage

**Via LiteLLM UI (Recommended)**:
1. Access LiteLLM Admin UI: `http://{your-fqdn}:4000`
2. Navigate to **"Usage"** → **"Old Usage"** → **"Customer Usage"** tab
3. View usage by customer email address:
   - **Customer**: Email address (e.g., sample@example.com)
   - **Spend**: Total cost
   - **Total Events**: Number of requests

**Note**: Budget settings cannot be configured via the UI. Use the API endpoints above to set budgets.

**Via API**:
```bash
curl -X GET 'http://{your-fqdn}:4000/customer/info?end_user_id=user@example.com' \
  -H 'Authorization: Bearer YOUR_MASTER_KEY'
```

**How it works**:
- OpenResty automatically attaches OAuth2 email to each API request
- LiteLLM automatically creates Customer record on first request
- LiteLLM tracks usage per email address
- Budget limits are enforced automatically
- Requests are rejected when user exceeds their limit

**Documentation**: [LiteLLM End User Budgets](https://docs.litellm.ai/docs/proxy/customers)

---

## 🛡️ Session Management (NEW)

### Force Logout Feature

Administrators can forcefully delete user sessions with automatic re-login prevention using a deletion flag system.

#### How It Works

1. **Admin deletes user session** via Token & Session Manager or API
2. **Deletion flag is created** in Redis (valid for 60 seconds)
3. **User attempts to access** within 60 seconds
4. **System checks deletion flag** and blocks session recreation
5. **401 error returned** with message: "Session has been revoked"
6. **User is redirected** to login screen
7. **After 60 seconds**, deletion flag expires automatically
8. **User can log in again** normally

#### Usage Methods

**Method 1: Token & Session Manager UI (Recommended)**

1. Access `http://{your-fqdn}/token-session-manager` (admin only)
2. Navigate to **Sessions** tab
3. Search for user by email
4. Click **Delete** button next to the user's session
5. Confirm deletion

**Expected response**:
```json
{
  "message": "User sessions deleted successfully",
  "user_email": "user@example.com",
  "deleted_count": 1,
  "deletion_flag_created": true,
  "deletion_flag_ttl": 60
}
```

**Method 2: API**

```bash
# Via internal port (bypass OAuth2)
curl -X POST http://localhost:8080/api/admin/sessions/revoke-user \
  -H "Content-Type: application/json" \
  -H "X-Forwarded-Email: admin@example.com" \
  -d '{"user_email":"user@example.com"}'
```

#### Technical Details

**Implementation**:
- **session_admin.lua**: Creates deletion flag on session deletion
- **active_user_tracker.lua**: Checks deletion flag before creating active_user
- **Deletion flag TTL**: 60 seconds (automatic expiration)

**Behavior**:
- ✅ Prevents automatic re-login after session deletion
- ✅ Returns clear error message to user
- ✅ Auto-expires after 60 seconds for normal re-login
- ✅ No impact on other users

**User Experience**:
```
Session deleted by admin
  ↓
User reloads page (within 60 seconds)
  ↓
401 Error: "Your session has been deleted by an administrator. Please log in again."
  ↓
Redirected to login screen
  ↓
After 60 seconds: Normal login available
```

---

## 📊 Monitoring

### Langfuse Dashboard

Access tracing and analytics:

```
http://{your-fqdn}:3000
```

**Metrics available**:
- Request count by user/model
- Token usage and costs
- Error rates
- Response times

### View Logs

```bash
# All services
sudo docker compose logs -f

# Specific service
sudo docker compose logs -f litellm
sudo docker compose logs -f openresty
```

---

## 🛠️ Management

### Token Management API

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/token/generate` | POST | Generate new JWT token |
| `/api/token/list` | GET | List user's tokens |
| `/api/token/info?token_id=xxx` | GET | Get token details |
| `/api/token/revoke` | POST | Revoke token |

### Session Management API (NEW)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/admin/sessions` | GET | List all sessions (admin only) |
| `/api/admin/sessions/revoke-user` | POST | Delete user sessions (admin only) |
| `/api/admin/sessions/stats` | GET | Get session statistics (admin only) |

### User Management

1. **Add User**: Add to Auth0 dashboard
2. **Remove User**: Delete from Auth0 → All tokens become invalid within 24 hours
3. **Force Logout**: Use session deletion feature (immediate effect)

---

## 🔒 Security

### Best Practices

- ✅ Store JWT tokens securely (environment variables or password managers)
- ✅ Rotate tokens regularly
- ✅ Use HTTPS in production
- ✅ Set `.env` file permissions: `chmod 600 .env`
- ✅ Enable MFA in Auth0
- ✅ Monitor Langfuse for suspicious activity
- ✅ Use session deletion feature for immediate user lockout

### OAuth2 Session Validation

**Current implementation**:
- JWT tokens are validated on every API request
- Token revocation is immediate via Redis blacklist
- OAuth2 email is attached to all LiteLLM API requests for per-user tracking
- **Session deletion with re-login prevention** (NEW)

**Planned enhancements**:
- OAuth2 session must exist and be valid
- Sessions will expire every 24 hours
- Unauthenticated OAuth2 users will lose access after 24 hours
- Automatic JWT token refresh (planned)

---

## 📚 Documentation

| Document | Description |
|----------|-------------|
| [QUICKSTART.md](docs/QUICKSTART.md) | 5-minute setup guide |
| [SETUP_DETAILED.md](docs/SETUP_DETAILED.md) | Detailed installation |
| [API_USAGE.md](docs/API_USAGE.md) | API reference |
| [OAUTH2_SESSION_CHECK_GUIDE.md](docs/OAUTH2_SESSION_CHECK_GUIDE.md) | Session validation feature |
| [OPERATIONS.md](docs/OPERATIONS.md) | Daily operations |
| [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Common issues |

---

## 🐛 Troubleshooting

### Common Issues

| Problem | Solution |
|---------|----------|
| Authentication loop | Check Auth0 callback URL configuration |
| JWT verification failed | Reinstall lua-resty-jwt |
| OAuth2 session expired | Re-authenticate in browser |
| Connection refused | Check container status: `docker compose ps` |
| Session deletion not working | Check deletion flag in Redis: `redis-cli GET "active_user_deleted:email"` |

### Debug Mode

Enable detailed logging in `nginx.conf`:

```nginx
error_log /var/log/nginx/error.log debug;
```

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- [LiteLLM](https://github.com/BerriAI/litellm) - LLM Proxy
- [OAuth2 Proxy](https://github.com/oauth2-proxy/oauth2-proxy) - OAuth2 Authentication
- [OpenResty](https://openresty.org/) - High-performance web platform
- [Langfuse](https://langfuse.com/) - LLM Observability
- [Auth0](https://auth0.com/) - Identity platform
- [Claude](https://www.anthropic.com/claude) (Anthropic) - AI Assistant for documentation and development support

---

## 📞 Support

- 📖 Documentation: Check the `docs/` directory
- 🐛 Issues: [GitHub Issues](https://github.com/nakacya/llm-gateway-oauth/issues)
- 💬 Discussions: [GitHub Discussions](https://github.com/nakacya/llm-gateway-oauth/discussions)

---

**Built with ❤️ for secure team LLM collaboration**
