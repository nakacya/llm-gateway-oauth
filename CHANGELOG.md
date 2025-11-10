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
- Display all active users with their session counts
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

**Instant BAN Feature** (7-day forced logout)
- Immediate user BAN capability for emergency situations
- All user sessions deleted instantly from Redis
- BAN record creation with 7-day TTL (604,800 seconds)
- Automatic OAuth2 authentication blocking during BAN period
- Auto-unban after 7 days + OAuth2 re-authentication required
- Unban functionality for administrators
- BAN status display with remaining time
- Comprehensive admin audit logging

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

### Changed

**Documentation** (Complete Overhaul)
- Updated README.md with comprehensive 4-tab dashboard documentation
- Updated README-ja.md with all new features in Japanese
- Added detailed usage instructions for Active Users, Cleanup tabs
- Enhanced troubleshooting section with BAN and cleanup issues
- Added migration guide and upgrade notes

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

### Fixed
- Phase 3 verification issue with Token API context resolved
- Orphaned token cleanup now properly handles user:tokens sets
- Cleanup logs display with expandable deletion details
- Session deletion now includes proper audit logging
- BAN status correctly updates in real-time

### Security
- Enhanced audit logging for all administrative actions
- Immediate threat response via instant BAN feature
- Improved session management visibility
- Better compliance with audit trail requirements

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
| 1.5.0 | 2025-11-10 | 4-tab dashboard, Instant BAN, Expandable logs, nginx v11.2 | +470 lines docs |
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

# 2. Update nginx.conf to v11.2
# (Download from GitHub or copy new version)

# 3. Update token_session_manager HTML to v4.0
# (Download from GitHub)

# 4. Restart services
sudo docker compose restart openresty

# 5. Verify deployment
curl -s http://localhost:8080/health | jq .
```

**No Breaking Changes**:
- All existing API endpoints remain functional
- No database migrations required
- No .env configuration changes needed

**New Features to Test**:
- Access `/token-session-manager` and verify 4 tabs visible
- Test Active Users tab with user search
- Test Instant BAN functionality (7-day lockout)
- Test Cleanup preview and execution
- Verify expandable deletion details in cleanup logs

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
# 1. Test Active Users API
curl -X GET http://your-fqdn/api/admin/sessions/active-users \
  -H "Cookie: _oauth2_proxy=YOUR_ADMIN_COOKIE"

# 2. Test BAN functionality
curl -X POST http://your-fqdn/api/admin/sessions/revoke-user \
  -H "Cookie: _oauth2_proxy=YOUR_ADMIN_COOKIE" \
  -H "Content-Type: application/json" \
  -d '{"user_email": "test@example.com"}'

# 3. Test Cleanup preview
curl -X GET http://your-fqdn/api/admin/redis/cleanup/preview \
  -H "Cookie: _oauth2_proxy=YOUR_ADMIN_COOKIE"

# 4. Test Cleanup execution
curl -X POST http://your-fqdn/api/admin/redis/cleanup \
  -H "Cookie: _oauth2_proxy=YOUR_ADMIN_COOKIE"

# 5. Test Cleanup logs
curl -X GET http://your-fqdn/api/admin/redis/cleanup/logs \
  -H "Cookie: _oauth2_proxy=YOUR_ADMIN_COOKIE"
```

**UI Testing**:
1. Open `http://your-fqdn/token-session-manager`
2. Verify all 4 tabs are visible and functional
3. Test search functionality in each tab
4. Test BAN/Unban operations in Active Users tab
5. Test Cleanup preview → execute → logs workflow

---

## Security Advisories

### Version 1.5.0 Security Features

**Instant BAN Feature**
- **Purpose**: Immediate user lockout for emergency situations
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

**Cleanup Operations**:
- Minimal Redis command usage
- Zero-downtime execution
- No impact on active sessions or tokens
- Efficient memory reclamation

---

## Known Issues

### Version 1.5.0

None reported. All features tested and operational.

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
