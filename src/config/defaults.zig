/// Default configuration values

// Server defaults
pub const listen_address = "127.0.0.1";
pub const listen_port = 8080;

// TLS defaults
pub const tls_enabled = false;

// Middleware defaults
pub const rate_limit_enabled = false;
pub const rate_limit_requests_per_minute = 60;

pub const auth_enabled = false;

pub const cache_enabled = false;
pub const cache_ttl_seconds = 300; // 5 minutes
