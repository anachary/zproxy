const std = @import("std");
const config = @import("config.zig");

/// TLS certificate manager
pub const Manager = struct {
    allocator: std.mem.Allocator,
    config: config.TlsConfig,
    certificates: std.StringHashMap(Certificate),
    
    /// TLS certificate
    const Certificate = struct {
        cert_data: []const u8,
        key_data: []const u8,
    };
    
    /// Initialize a new TLS manager
    pub fn init(allocator: std.mem.Allocator, tls_config: anytype) !Manager {
        var manager = Manager{
            .allocator = allocator,
            .config = try config.TlsConfig.fromConfig(allocator, tls_config),
            .certificates = std.StringHashMap(Certificate).init(allocator),
        };
        
        // Load certificates if TLS is enabled
        if (manager.config.enabled) {
            try manager.loadCertificates();
        }
        
        return manager;
    }
    
    /// Clean up resources
    pub fn deinit(self: *Manager) void {
        self.config.deinit(self.allocator);
        
        var it = self.certificates.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.cert_data);
            self.allocator.free(entry.value_ptr.key_data);
        }
        self.certificates.deinit();
    }
    
    /// Load certificates from files
    fn loadCertificates(self: *Manager) !void {
        // Load default certificate
        if (self.config.cert_path) |cert_path| {
            if (self.config.key_path) |key_path| {
                try self.loadCertificate("default", cert_path, key_path);
            }
        }
        
        // Load domain-specific certificates
        for (self.config.domain_certs) |domain_cert| {
            try self.loadCertificate(
                domain_cert.domain,
                domain_cert.cert_path,
                domain_cert.key_path,
            );
        }
    }
    
    /// Load a certificate from files
    fn loadCertificate(self: *Manager, domain: []const u8, cert_path: []const u8, key_path: []const u8) !void {
        // Read certificate file
        const cert_file = try std.fs.cwd().openFile(cert_path, .{});
        defer cert_file.close();
        
        const cert_size = try cert_file.getEndPos();
        const cert_data = try self.allocator.alloc(u8, cert_size);
        errdefer self.allocator.free(cert_data);
        
        const cert_bytes_read = try cert_file.readAll(cert_data);
        if (cert_bytes_read != cert_size) {
            return error.IncompleteRead;
        }
        
        // Read key file
        const key_file = try std.fs.cwd().openFile(key_path, .{});
        defer key_file.close();
        
        const key_size = try key_file.getEndPos();
        const key_data = try self.allocator.alloc(u8, key_size);
        errdefer self.allocator.free(key_data);
        
        const key_bytes_read = try key_file.readAll(key_data);
        if (key_bytes_read != key_size) {
            return error.IncompleteRead;
        }
        
        // Store certificate
        const domain_copy = try self.allocator.dupe(u8, domain);
        errdefer self.allocator.free(domain_copy);
        
        try self.certificates.put(domain_copy, Certificate{
            .cert_data = cert_data,
            .key_data = key_data,
        });
    }
    
    /// Get a certificate for a domain
    pub fn getCertificate(self: *const Manager, domain: []const u8) ?Certificate {
        // Try to find a certificate for the specific domain
        if (self.certificates.get(domain)) |cert| {
            return cert;
        }
        
        // Fall back to default certificate
        return self.certificates.get("default");
    }
};
