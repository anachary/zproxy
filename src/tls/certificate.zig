const std = @import("std");
const logger = @import("../utils/logger.zig");

/// Certificate
pub const Certificate = struct {
    allocator: std.mem.Allocator,
    cert_data: []const u8,
    key_data: []const u8,
    
    /// Load a certificate from files
    pub fn load(allocator: std.mem.Allocator, cert_file: []const u8, key_file: []const u8) !Certificate {
        logger.debug("Loading certificate from {s} and {s}", .{ cert_file, key_file });
        
        // Open certificate file
        const cert_file_handle = try std.fs.cwd().openFile(cert_file, .{});
        defer cert_file_handle.close();
        
        // Read certificate data
        const cert_size = try cert_file_handle.getEndPos();
        const cert_data = try allocator.alloc(u8, cert_size);
        errdefer allocator.free(cert_data);
        
        const cert_bytes_read = try cert_file_handle.readAll(cert_data);
        if (cert_bytes_read != cert_size) {
            return error.IncompleteRead;
        }
        
        // Open key file
        const key_file_handle = try std.fs.cwd().openFile(key_file, .{});
        defer key_file_handle.close();
        
        // Read key data
        const key_size = try key_file_handle.getEndPos();
        const key_data = try allocator.alloc(u8, key_size);
        errdefer allocator.free(key_data);
        
        const key_bytes_read = try key_file_handle.readAll(key_data);
        if (key_bytes_read != key_size) {
            allocator.free(cert_data);
            return error.IncompleteRead;
        }
        
        return Certificate{
            .allocator = allocator,
            .cert_data = cert_data,
            .key_data = key_data,
        };
    }
    
    /// Clean up certificate resources
    pub fn deinit(self: *Certificate) void {
        self.allocator.free(self.cert_data);
        self.allocator.free(self.key_data);
    }
};

/// Certificate chain
pub const CertificateChain = struct {
    allocator: std.mem.Allocator,
    certificates: []Certificate,
    
    /// Initialize a new certificate chain
    pub fn init(allocator: std.mem.Allocator) CertificateChain {
        return CertificateChain{
            .allocator = allocator,
            .certificates = &[_]Certificate{},
        };
    }
    
    /// Add a certificate to the chain
    pub fn addCertificate(self: *CertificateChain, cert: Certificate) !void {
        const new_certs = try self.allocator.alloc(Certificate, self.certificates.len + 1);
        std.mem.copy(Certificate, new_certs, self.certificates);
        new_certs[self.certificates.len] = cert;
        
        self.allocator.free(self.certificates);
        self.certificates = new_certs;
    }
    
    /// Clean up certificate chain resources
    pub fn deinit(self: *CertificateChain) void {
        for (self.certificates) |*cert| {
            cert.deinit();
        }
        self.allocator.free(self.certificates);
    }
};
