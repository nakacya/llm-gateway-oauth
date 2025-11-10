# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Planned
- OAuth2 session validation with 24-hour re-authentication
- Automatic JWT token refresh
- Scheduled Redis cleanup automation (cron job)
- Prometheus metrics integration
- Slack notification for cleanup alerts

---

## [1.5.0] - 2025-11-10

### Added

#### Token & Session Manager v4.0 - 4-Tab Unified Dashboard

**👥 Active Users Tab**
- Real-time active user monitoring with session tracking
- **Unified display of both OAuth2 and JWT token users** (NEW)
- Display all active users with their session/token counts
- **Identify authentication method (OAuth2 / JWT)** (NEW)
- Track last access time and expiration
- User statistics dashboard (total users, banned users, active sessions)
- Search users by email address
- Cleanup expired user data functionality

**🔐 Sessions Tab** (Enhanced)
- View all active OAuth2 sessions
- Session statistics (total sessions, unique users)
- Search sessions by email
- Force logout via session deletion
- Monitor session TTL (Time To Live)
- Individual session revocation with audit logging

**🎫 Tokens Tab** (Enhanced)
- View all JWT tokens across users
- Token statistics (total, active, expired, revoked)
- Search by email or token name
- Revoke active tokens
- Real-time status updates
- Admin-level token oversight

**🧹 Cleanup Tab**
- **Preview Mode**: View cleanup targets before deletion
  - Orphaned JWT token IDs count
  - Orphaned metadata count
  - Estimated memory to be freed
  - Detailed JSON preview of items to be deleted
- **Execute Mode**: Manual cleanup operations
  - Delete orphaned token IDs from user:tokens sets
  - Remove orphaned active_user_metadata entries
  - Clean up empty token sets
  - View execution results with deletion count and freed memory
- **Logs Mode**: View cleanup history with detailed audit trail
  - **Expandable deletion details per execution** (v4.0 feature)
  - User emails and token IDs
  - Deletion reasons and timestamps
  - Color-coded deletion types and reasons
  - 30-day log retention
  - Full execution history with pagination

#### Security Features

**Instant BAN Feature** (7-day forced logout) - **Enhanced with JWT Token Support**
- Immediate user BAN capability for emergency situations
- **Works across all access methods** (NEW):
  - ✅ OAuth2 browser access
  - ✅ JWT token API calls
  - ✅ Roo Code / VS Code extension
  - ✅ CLI tools
- All user sessions deleted instantly from Redis
- BAN record creation with 7-day TTL (604,800 seconds)
- **OAuth2**: Automatic authentication blocking during BAN period
- **JWT Token**: 401 Unauthorized with BAN remaining time display
- Auto-unban after 7 days + re-authentication required
- Unban functionality for administrators
- BAN status display with remaining time
- Comprehensive admin audit logging

**Active User Tracking Enhancement**
- **JWT token users now tracked in Active Users tab** (NEW)
- Automatic user tracking on JWT token authentication
- Track authentication method (OAuth2 vs JWT) in metadata
- Session/token count tracking for all users
- Unified management of OAuth2 and JWT token users
- Real-time activity monitoring for all access methods

#### API Endpoints (New)
```
GET    /api/admin/sessions/active-users       - List active users with stats
POST   /api/admin/sessions/revoke-user        - BAN user (revoke all sessions)
DELETE /api/admin/sessions/unban/{email}      - Unban user
GET    /api/admin/redis/cleanup/preview       - Preview cleanup targets
POST   /api/admin/redis/cleanup               - Execute cleanup
GET    /api/admin/redis/cleanup/logs          - View cleanup history
```

#### Expandable Deletion Details (v4.0)
- Toggle button to show/hide detailed deletion logs
- Formatted display with user emails, token IDs, reasons
- Color-coded badges for deletion types
- Scrollable view for large deletion sets (max 400px)
- Item count badges on expand buttons
- Improved audit trail visibility

#### Implementation Details (auth_handler.lua v2.0)

**BAN Status Check for JWT Tokens**
- Added Redis connection and BAN check in `auth_handler.lua`
- Checks `active_user_deleted:{email}` before processing JWT requests
- Returns 401 Unauthorized with BAN duration message
- Graceful fallback on Redis connection failure (availability priority)

**Active User Tracking for JWT Tokens**
- Creates `active_user:{email}` key with JWT token ID
- Saves `active_user_metadata:{email}` with full tracking data:
  - Email, created_at, last_access, expires_at
  - session_count, auth_method: "jwt", token_name
- Adds user to `active_users` set
- TTL management (24 hours, set only on first creation)
- Compatible with existing OAuth2 tracking structure

### Changed

**Documentation** (Complete Overhaul)
- Updated README.md with comprehensive JWT BAN support documentation
- Updated README-ja.md with all JWT tracking features in Japanese
- Added detailed JWT token BAN flow and user experience
- Enhanced troubleshooting section with JWT BAN issues
- Updated architecture diagram with BAN check flow
- Added JWT token user examples throughout documentation

**nginx.conf v11.2** (Cleanup Release)
- Removed unused Port 80 `/api/token/` endpoint (22 lines)
- Improved configuration readability and maintainability
- No breaking changes - all functionality preserved
- Fixed Phase 3 verification "Token API context" skip issue
- Reduced total lines from 658 to 650 (-8 lines)

**UI/UX Improvements**
- Enhanced responsive design across all tabs
- Improved search functionality with real-time filtering
- Better visual feedback for administrative actions
- Consistent color-coding for status indicators
- Loading states and error handling improved
- **Active Users tab now shows both OAuth2 and JWT users** (NEW)

**Lua Module Updates**
- `auth_handler.lua`: Added BAN check and Active User tracking
- `active_user_tracker.lua`: Already had BAN check for OAuth2
- Unified BAN enforcement across all authentication methods
- Consistent metadata structure for both OAuth2 and JWT users

### Fixed
- **Critical Security Fix**: JWT token users can now be banned effectively
- **Fixed**: JWT token-only users not appearing in Active Users tab
- **Fixed**: BAN feature only worked for OAuth2 users, not JWT users
- Phase 3 verification issue with Token API context resolved
- Orphaned token cleanup now properly handles user:tokens sets
- Cleanup logs display with expandable deletion details
- Session deletion now includes proper audit logging
- BAN status correctly updates in real-time across all authentication methods

### Security
- **Critical**: JWT token BAN enforcement now fully operational
- Enhanced audit logging for all administrative actions
- Immediate threat response via instant BAN across all access methods
- Improved session management visibility for both OAuth2 and JWT
- Better compliance with audit trail requirements
- Consistent security posture regardless of authentication method

---

## [1.4.0] - 2025-11-08

### Added
- Token & Session Manager v3.0 with dual-tab interface
  - OAuth2 Sessions tab with force logout capability
  - JWT Tokens tab with admin-level token management
  - Session statistics dashboard
  - Real-time session monitoring

### Changed
- **nginx.conf v11.1**: Consolidated user tracking code
  - Refactored duplicate Lua code into global `_G.track_user()` function
  - Changed debug logging to warn level for production
  - Improved code maintainability and readability
  - Reduced code duplication across locations

### Improved
- Enhanced session management capabilities
- Better admin audit logging
- More consistent error handling

---

## [1.3.0] - 2025-11-07

### Added
- **Session Deletion with Force Logout**
  - Admin can delete individual sessions via UI
  - Immediate user logout on next request
  - Automatic redirect to Auth0 login screen
  - Session management API endpoints
  - Support for multiple session key patterns

### Changed
- Enhanced session management capabilities
- Improved Redis session key search patterns
- Better error handling for session operations

### Security
- Immediate session revocation for security incidents
- Enhanced admin audit logging for session deletions

---

## [1.2.0] - 2025-11-05

### Added
- **OAuth2 Session Check Feature**
  - Real-time session validation on each request
  - Per-user usage tracking with OAuth2 email
  - Session expiration monitoring
  - Enhanced security with session state verification

### Security
- Enhanced token blacklist management
- Improved Redis-based session storage
- Better session lifecycle management

---

## [1.1.0] - 2025-10-15

### Added
- **Token Manager UI** (User Self-Service)
  - Generate JWT tokens via web interface at `/token-manager`
  - View token list and detailed information
  - Revoke tokens individually
  - Custom expiration settings (up to 90 days)
  - User-friendly token management dashboard

### Changed
- Improved JWT token validation logic
- Enhanced Lua module integration
- Better error messages for token operations

---

## [1.0.0] - 2025-10-01

### Initial Release

#### Core Features

**Dual Authentication System**
- OAuth2 authentication via Auth0 for browser-based access
- JWT token authentication for API/CLI clients (up to 90 days)
- OpenResty (nginx + Lua) high-performance gateway
- Seamless integration between OAuth2 and JWT flows

**LiteLLM Integration**
- Multi-model support (Anthropic Claude, OpenAI GPT, etc.)
- Unified API gateway with consistent interface
- Cost tracking per user and model
- Budget limits per user (optional)

**Observability & Analytics**
- Langfuse integration for comprehensive request tracing
- Per-user usage analytics with OAuth2 email attachment
- Model-specific cost tracking
- Request/response logging for debugging
- Performance metrics and monitoring

**Infrastructure**
- Docker Compose deployment for easy setup
- PostgreSQL for metadata storage and persistence
- Redis for session and token management
- ClickHouse for analytics and reporting
- Ubuntu 24.04 compatible

#### Security Features

- JWT token blacklist management
- Immediate token revocation on user removal
- Redis-based session storage with TTL
- OAuth2 email attached to all API requests for tracking
- Secure cookie handling with OAuth2 Proxy
- HTTPS-ready configuration

#### API Endpoints (Initial)
```
POST /api/token/generate      - Generate new JWT token
GET  /api/token/list          - List user's tokens
GET  /api/token/info          - Get token details
POST /api/token/revoke        - Revoke token
POST /v1/messages             - LLM API proxy (Claude-compatible)
```

#### Management Interfaces

- Token Manager (`/token-manager`) - User self-service portal
- Admin Manager (`/admin-manager`) - Admin user management

#### Development Tools Support

- Roo Code VS Code extension compatibility
- CLI-friendly JWT authentication
- Example configurations for common tools

---

## Version History Summary

| Version | Release Date | Key Features | Lines Changed |
|---------|-------------|--------------|---------------|
| 1.5.0 | 2025-11-10 | 4-tab dashboard, JWT BAN support, Active User tracking, nginx v11.2 | +194 lines (auth_handler.lua) |
| 1.4.0 | 2025-11-08 | Dual-tab manager, nginx v11.1, Code consolidation | Refactored |
| 1.3.0 | 2025-11-07 | Session deletion, Force logout | +150 lines |
| 1.2.0 | 2025-11-05 | OAuth2 session check, Real-time validation | +200 lines |
| 1.1.0 | 2025-10-15 | Token Manager UI, Self-service | +300 lines |
| 1.0.0 | 2025-10-01 | Initial release with OAuth2 + JWT | Base release |

---

## Upgrade Notes

### Upgrading to 1.5.0 from 1.4.x

**Required Steps**:
```bash
# 1. Backup current configuration
cd ~/oauth2
cp nginx.conf nginx.conf.backup_v11.1
cp lua/auth_handler.lua lua/auth_handler.lua.backup

# 2. Update nginx.conf to v11.2
# (Download from GitHub or copy new version)

# 3. Update auth_handler.lua to v2.0 with BAN check
# (Download from GitHub)

# 4. Update token_session_manager HTML to v4.0
# (Download from GitHub)

# 5. Restart services
sudo docker compose restart openresty

# 6. Verify deployment
curl -s http://localhost:8080/health | jq .
```

**No Breaking Changes**:
- All existing API endpoints remain functional
- No database migrations required
- No .env configuration changes needed
- Existing JWT tokens continue to work

**New Features to Test**:
- Access `/token-session-manager` and verify 4 tabs visible
- Test Active Users tab with both OAuth2 and JWT users
- Test Instant BAN functionality on JWT token users
- Verify JWT token users appear in Active Users tab
- Test BAN enforcement across all access methods (OAuth2, JWT, Roo Code, CLI)
- Test Cleanup preview and execution
- Verify expandable deletion details in cleanup logs

**Critical Security Testing**:
```bash
# 1. Test JWT token user tracking
# - Use JWT token to access API
# - Verify user appears in Active Users tab
# - Verify auth_method: "jwt" in metadata

# 2. Test JWT token user BAN
# - BAN a JWT token user via Active Users tab
# - Attempt API access with banned user's JWT token
# - Expected: 401 Unauthorized with "User is banned for X days Y hours"

# 3. Test BAN enforcement
# - Verify OAuth2 users cannot log in when banned
# - Verify JWT token users get 401 error when banned
# - Verify Roo Code / CLI tools respect BAN status

# 4. Test BAN unban
# - Unban a user
# - Verify OAuth2 user can log in again
# - Verify JWT token user can access API again
```

**Optional Configuration**:
```bash
# Add to .env (optional, defaults shown)
CLEANUP_LOG_RETENTION_DAYS=30  # Cleanup log retention period
```

### Upgrading to 1.4.0 from 1.3.x

**Required Steps**:
1. Update nginx.conf to v11.1
2. Deploy token_session_manager v3.0
3. No breaking changes or migrations

### Upgrading to 1.3.0 from 1.2.x

**Required Steps**:
1. Deploy session management Lua modules
2. Test session deletion functionality
3. Verify force logout behavior

---

## Migration Guide

### From 1.4.x to 1.5.0

**Backward Compatibility**: ✅ Fully backward compatible

**Testing Checklist**:
```bash
# 1. Test Active Users API (OAuth2 and JWT users)
curl -X GET http://your-fqdn/api/admin/sessions/active-users \
  -H "Cookie: _oauth2_proxy=YOUR_ADMIN_COOKIE"

# 2. Test BAN functionality (OAuth2 user)
curl -X POST http://your-fqdn/api/admin/sessions/revoke-user \
  -H "Cookie: _oauth2_proxy=YOUR_ADMIN_COOKIE" \
  -H "Content-Type: application/json" \
  -d '{"user_email": "oauth2-user@example.com"}'

# 3. Test JWT token with banned user
curl -X POST http://your-fqdn/v1/messages \
  -H "Authorization: Bearer BANNED_USER_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"model":"claude-sonnet-4","max_tokens":100,"messages":[{"role":"user","content":"test"}]}'
# Expected: 401 Unauthorized with BAN message

# 4. Test JWT token with active user (should work)
curl -X POST http://your-fqdn/v1/messages \
  -H "Authorization: Bearer ACTIVE_USER_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"model":"claude-sonnet-4","max_tokens":100,"messages":[{"role":"user","content":"test"}]}'
# Expected: 200 OK with response

# 5. Test Cleanup preview
curl -X GET http://your-fqdn/api/admin/redis/cleanup/preview \
  -H "Cookie: _oauth2_proxy=YOUR_ADMIN_COOKIE"

# 6. Test Cleanup execution
curl -X POST http://your-fqdn/api/admin/redis/cleanup \
  -H "Cookie: _oauth2_proxy=YOUR_ADMIN_COOKIE"

# 7. Test Cleanup logs
curl -X GET http://your-fqdn/api/admin/redis/cleanup/logs \
  -H "Cookie: _oauth2_proxy=YOUR_ADMIN_COOKIE"
```

**UI Testing**:
1. Open `http://your-fqdn/token-session-manager`
2. Verify all 4 tabs are visible and functional
3. Test search functionality in each tab
4. **Test that JWT token users appear in Active Users tab**
5. **Test BAN operation on JWT token user**
6. Verify auth_method (OAuth2/JWT) is displayed
7. Test BAN/Unban operations in Active Users tab
8. Test Cleanup preview → execute → logs workflow

---

## Security Advisories

### Version 1.5.0 Security Enhancements

**Critical Security Fix: JWT Token BAN Enforcement**
- **Issue**: Previously, users banned via token-session-manager could still access LiteLLM using JWT tokens
- **Fixed**: JWT token authentication now checks BAN status before processing requests
- **Impact**: All access methods (OAuth2, JWT, Roo Code, CLI) now respect BAN status
- **Response**: Banned JWT users receive 401 Unauthorized with remaining BAN time
- **Recommendation**: Re-test BAN functionality after upgrade to ensure proper enforcement

**Active User Tracking Enhancement**
- **Purpose**: Complete visibility of all users regardless of authentication method
- **Benefit**: Administrators can now track and manage JWT token-only users
- **Use Case**: Users accessing exclusively via API/CLI/Roo Code are now visible
- **Audit Trail**: All user activity tracked with authentication method recorded

**Instant BAN Feature - Universal Coverage**
- **Purpose**: Immediate user lockout for emergency situations
- **Coverage**: Works across all access methods:
  - OAuth2 browser sessions
  - JWT token API calls
  - Roo Code VS Code extension
  - CLI tools
- **Duration**: 7 days (604,800 seconds)
- **Use Cases**: Employee departure, security incident, suspicious activity
- **Audit Trail**: All BAN operations logged with admin email and timestamp
- **Best Practice**: Use for time-sensitive security threats requiring immediate action

**Cleanup Audit Logs**
- **Purpose**: Complete audit trail for Redis maintenance operations
- **Retention**: 30 days
- **Details**: User emails, token IDs, deletion reasons, timestamps
- **Best Practice**: Review logs regularly for anomalies or unexpected deletions

### Version 1.3.0 Security Features

**Force Logout**
- **Purpose**: Immediate session revocation
- **Recommendation**: Regular session audits via Token & Session Manager
- **Best Practice**: Use for non-emergency user access revocation

### Version 1.0.0 Security Model

**JWT Token Lifetime**
- **Maximum**: 90 days
- **Recommended**: 30 days for production environments
- **Rotation**: Regular token rotation for enhanced security

---

## Performance Notes

### Version 1.5.0

**nginx.conf v11.2 Improvements**:
- Removed 22 lines of unused code
- No performance impact (positive or negative)
- Maintained Phase 7 performance benchmarks:
  - Average response time: 0.912ms
  - Standard deviation: 0.24ms

**auth_handler.lua v2.0 Performance**:
- Added Redis BAN check: ~1-2ms overhead
- Active User tracking: ~2-3ms overhead
- Total additional latency: ~3-5ms per JWT request
- Redis connection pooling minimizes overhead
- Graceful degradation on Redis failure (availability priority)

**Cleanup Operations**:
- Minimal Redis command usage
- Zero-downtime execution
- No impact on active sessions or tokens
- Efficient memory reclamation

---

## Known Issues

### Version 1.5.0

None reported. All features tested and operational.

**Tested Scenarios**:
- ✅ OAuth2 user BAN enforcement
- ✅ JWT token user BAN enforcement
- ✅ JWT token user Active User tracking
- ✅ Roo Code BAN respect
- ✅ CLI tool BAN respect
- ✅ BAN unban flow
- ✅ Mixed OAuth2 and JWT user display in Active Users tab

### Version 1.4.0

None reported.

### Version 1.3.0

None reported.

---

## Deprecations

### Version 1.5.0

**Removed**:
- Port 80 `/api/token/` endpoint (nginx.conf v11.2)
  - **Reason**: Non-functional, proxied to OAuth2 Proxy which lacks this endpoint
  - **Impact**: None - endpoint was never used (0 access log entries)
  - **Migration**: Use Port 8080 endpoints (no changes needed by users)

---

## Contributors

- **nakacya** (nakacya@gmail.com) - Project Lead & Developer
- **Claude (Anthropic)** - AI Assistant for development and documentation

---

## Support & Resources

### Documentation
- **Quick Start**: See `docs/QUICKSTART.md` for 5-minute setup
- **API Reference**: See `docs/API_USAGE.md` for complete API documentation
- **Operations Guide**: See `docs/OPERATIONS.md` for daily operations
- **Troubleshooting**: See `docs/TROUBLESHOOTING.md` for common issues

### Community
- **GitHub Repository**: https://github.com/nakacya/llm-gateway-oauth
- **Issues**: https://github.com/nakacya/llm-gateway-oauth/issues
- **Discussions**: https://github.com/nakacya/llm-gateway-oauth/discussions

### Production Environment
- **Gateway**: litellm.nakacya.jp
- **Management**: https://litellm.nakacya.jp/token-session-manager
- **LiteLLM UI**: https://litellm.nakacya.jp:4000
- **Langfuse**: https://litellm.nakacya.jp:3000

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## Acknowledgments

### Open Source Dependencies
- [LiteLLM](https://github.com/BerriAI/litellm) - Multi-provider LLM proxy
- [OAuth2 Proxy](https://github.com/oauth2-proxy/oauth2-proxy) - OAuth2 authentication
- [OpenResty](https://openresty.org/) - High-performance web platform
- [Langfuse](https://langfuse.com/) - LLM observability and tracing
- [Auth0](https://auth0.com/) - Identity platform and authentication

### LLM Providers
- [Anthropic](https://www.anthropic.com/) - Claude models
- [OpenAI](https://openai.com/) - GPT models

---

**Last Updated**: 2025-11-10
**Document Version**: 1.5.0
