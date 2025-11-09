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
  - **Session deletion with force logout** (NEW)
  - OAuth2 session check (planned: daily re-authentication)

- **📊 Complete Observability**
  - Real-time tracing with Langfuse
  - Per-user usage analytics (OAuth2 email attached to all API requests)
  - Cost tracking by model/user
  - Individual user budget limits available

- **🔄 Token & Session Management**
  - **Unified web-based management UI** (NEW)
  - Multiple tokens per user
  - Custom expiration settings
  - **Real-time session monitoring** (NEW)
  - **Force logout functionality** (NEW)

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
│  - Request Routing                   │
└──────┬───────────┬───────────────────┘
       │           │
       │           └──────────┐
       │                      ↓
       │                ┌──────────┐
       │                │  Redis   │
       │                │ (Tokens  │
       │                │  Sessions)│
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
3. Access Token & Session Manager at `http://{your-fqdn}/token-session-manager`
4. Manage JWT tokens and sessions through the unified web UI

**Available UIs**:
- **Token Manager** (`/token-manager`): Generate and manage your API tokens
- **Token & Session Manager** (`/token-session-manager`): Unified token and session management with real-time monitoring (admin only)
- **Admin Manager** (`/admin-manager`): Admin panel for user management (admin only)

### Token & Session Manager Features

The unified management interface provides:

**Tokens Tab**:
- View all JWT tokens across users
- Token statistics (total, active, expired, revoked)
- Search by email or token name
- Revoke active tokens
- Real-time status updates

**Sessions Tab**:
- View all active OAuth2 sessions
- Session statistics (total sessions, unique users)
- Search by email
- Force logout users by deleting sessions
- Monitor session TTL (Time To Live)

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

Administrators can forcefully delete user sessions to immediately revoke access. The system provides both UI-based and API-based management.

#### How It Works

1. **Admin deletes user session** via Token & Session Manager UI or API
2. **Session is removed** from Redis immediately
3. **User's next request fails** with 401 Unauthorized
4. **User is redirected** to login screen automatically
5. **User must re-authenticate** to regain access

#### Usage Methods

**Method 1: Token & Session Manager UI (Recommended)**

1. Access `http://{your-fqdn}/token-session-manager` (admin only)
2. Click on **Sessions** tab
3. Search for user by email address
4. Click **Delete** button next to the user's session
5. Confirm deletion in the dialog

**Expected UI behavior**:
- Success message displayed: "Session を削除しました"
- Session list automatically refreshes
- Deleted session no longer appears in the list

**Method 2: Delete Single Session (API)**

```bash
# Get session key from UI or API, then delete
curl -X DELETE http://{your-fqdn}/api/admin/sessions/{SESSION_KEY} \
  -H "Cookie: _oauth2_proxy=YOUR_ADMIN_COOKIE"
```

**Expected response**:
```json
{
  "message": "Session deleted successfully",
  "session_key": "_oauth2_proxy-abc123...",
  "deleted_by": "admin@example.com"
}
```

**Method 3: Delete All User Sessions (API)**

```bash
# Delete all sessions for a specific user
curl -X POST http://{your-fqdn}/api/admin/sessions/revoke-user \
  -H "Cookie: _oauth2_proxy=YOUR_ADMIN_COOKIE" \
  -H "Content-Type: application/json" \
  -d '{
    "user_email": "user@example.com"
  }'
```

**Expected response**:
```json
{
  "message": "User sessions deleted successfully",
  "user_email": "user@example.com",
  "deleted_count": 2,
  "deleted_by": "admin@example.com"
}
```

#### Technical Details

**Implementation**:
- **session_admin.lua**: Handles all session management API endpoints
- **OAuth2 Proxy**: Stores sessions in Redis with key pattern `_oauth2_proxy-*`
- **Session data**: Contains user email, creation time, expiration, and auth metadata

**Session Key Patterns Searched**:
```
_oauth2_proxy-*      # Primary pattern (hyphen format)
_oauth2_proxy_*      # Alternate pattern (underscore format)
_oauth2_proxy:*      # Alternate pattern (colon format)
oauth2-*             # Legacy pattern
oauth2_*             # Legacy pattern
session:*            # Generic pattern
```

**Behavior**:
- ✅ Immediate session deletion from Redis
- ✅ User automatically logged out on next request
- ✅ Multiple sessions per user supported
- ✅ Admin audit logging included
- ✅ No impact on other users' sessions

**User Experience**:
```
Session deleted by admin
  ↓
User continues browsing
  ↓
Next request to any protected endpoint
  ↓
401 Unauthorized: Cookie not found or invalid
  ↓
Automatic redirect to Auth0 login screen
  ↓
User must log in again to access system
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

| Endpoint | Method | Description | Auth Required |
|----------|--------|-------------|---------------|
| `/api/admin/sessions` | GET | List all active sessions | Admin only |
| `/api/admin/sessions/{session_key}` | DELETE | Delete specific session | Admin only |
| `/api/admin/sessions/revoke-user` | POST | Delete all sessions for a user | Admin only |
| `/api/admin/sessions/stats` | GET | Get session statistics | Admin only |

#### Session API Examples

**List All Sessions**:
```bash
curl http://{your-fqdn}/api/admin/sessions \
  -H "Cookie: _oauth2_proxy=YOUR_ADMIN_COOKIE"
```

**Get Session Statistics**:
```bash
curl http://{your-fqdn}/api/admin/sessions/stats \
  -H "Cookie: _oauth2_proxy=YOUR_ADMIN_COOKIE"
```

Response:
```json
{
  "total_sessions": 15,
  "unique_users": 8,
  "user_sessions": {
    "user1@example.com": 2,
    "user2@example.com": 1,
    "admin@example.com": 3
  }
}
```

### User Management

1. **Add User**: Add to Auth0 dashboard
2. **Remove User**: Delete from Auth0 → All tokens become invalid within 24 hours
3. **Force Logout**: Use session deletion feature via UI or API (immediate effect)

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
- ✅ Regularly audit active sessions via Token & Session Manager

### OAuth2 Session Validation

**Current implementation**:
- JWT tokens are validated on every API request
- Token revocation is immediate via Redis blacklist
- OAuth2 email is attached to all LiteLLM API requests for per-user tracking
- **Session deletion with force logout** (NEW)
- **Real-time session monitoring** (NEW)

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
| Session deletion not working | Verify Redis connection and session key format |
| Can't see sessions in UI | Ensure you're logged in as admin user |

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
