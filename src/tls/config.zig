const std = @import("std");

/// Domain-specific certificate configuration
pub const DomainCert = struct {
    domain: []const u8,
    cert_path: []const u8,
    key_path: []const u8,
};

/// TLS configuration
pub const TlsConfig = struct {
    enabled: bool,
    cert_path: ?[]const u8,
    key_path: ?[]const u8,
    domain_certs: []DomainCert,
    
    /// Create TLS config from a generic config
    pub fn fromConfig(allocator: std.mem.Allocator, config: anytype) !TlsConfig {
        var tls_config = TlsConfig{
            .enabled = if (@hasField(@TypeOf(config), "enabled")) config.enabled else false,
            .cert_path = null,
            .key_path = null,
            .domain_certs = &[_]DomainCert{},
        };
        
        // Copy cert and key paths
        if (@hasField(@TypeOf(config), "cert_path")) {
            if (config.cert_path) |cert_path| {
                tls_config.cert_path = try allocator.dupe(u8, cert_path);
            }
        }
        
        if (@hasField(@TypeOf(config), "key_path")) {
            if (config.key_path) |key_path| {
                tls_config.key_path = try allocator.dupe(u8, key_path);
            }
        }
        
        // Copy domain certificates
        if (@hasField(@TypeOf(config), "domain_certs")) {
            const domain_certs = try allocator.alloc(DomainCert, config.domain_certs.len);
            
            for (config.domain_certs, 0..) |domain_cert, i| {
                domain_certs[i] = DomainCert{
                    .domain = try allocator.dupe(u8, domain_cert.domain),
                    .cert_path = try allocator.dupe(u8, domain_cert.cert_path),
                    .key_path = try allocator.dupe(u8, domain_cert.key_path),
                };
            }
            
            tls_config.domain_certs = domain_certs;
        }
        
        return tls_config;
    }
    
    /// Clean up resources
    pub fn deinit(self: *TlsConfig, allocator: std.mem.Allocator) void {
        if (self.cert_path) |cert_path| {
            allocator.free(cert_path);
            self.cert_path = null;
        }
        
        if (self.key_path) |key_path| {
            allocator.free(key_path);
            self.key_path = null;
        }
        
        for (self.domain_certs) |*domain_cert| {
            allocator.free(domain_cert.domain);
            allocator.free(domain_cert.cert_path);
            allocator.free(domain_cert.key_path);
        }
        
        if (self.domain_certs.len > 0) {
            allocator.free(self.domain_certs);
            self.domain_certs = &[_]DomainCert{};
        }
    }
};
