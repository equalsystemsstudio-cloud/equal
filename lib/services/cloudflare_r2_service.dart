import 'dart:typed_data';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

class CloudflareR2Service {
  static final CloudflareR2Service _instance = CloudflareR2Service._internal();
  factory CloudflareR2Service() => _instance;
  CloudflareR2Service._internal();

  // Cloudflare R2 Configuration
  static const String _accessKeyId = 'c024226c4d9667034eb08c20815b5d50';
  static const String _secretAccessKey = '40016492ac38e168db28c54d0e983941c475c32a1d91a6735a5fe92f602ea5f1';
  static const String _endpoint = 'https://27e3a9baccd9653e1ade329045460213.r2.cloudflarestorage.com';
  static const String _region = 'auto'; // R2 uses 'auto' region
  
  // Bucket names (matching current Supabase structure)
  static const String profileImagesBucket = 'profile-images';
  static const String postImagesBucket = 'post-images';
  static const String postVideosBucket = 'post-videos';
  static const String postAudioBucket = 'post-audio';
  static const String thumbnailsBucket = 'thumbnails';

  /// Upload file to Cloudflare R2
  Future<String> uploadFile({
    required String bucket,
    required String fileName,
    required Uint8List fileBytes,
    String? contentType,
  }) async {
    try {
      final url = '$_endpoint/$bucket/$fileName';
      final timestamp = DateTime.now().toUtc();
      final dateStamp = _formatDateStamp(timestamp);
      final amzDate = _formatAmzDate(timestamp);
      
      // Create canonical request
      final canonicalRequest = _createCanonicalRequest(
        method: 'PUT',
        path: '/$bucket/$fileName',
        host: Uri.parse(_endpoint).host,
        amzDate: amzDate,
        payloadHash: _sha256Hash(fileBytes),
        contentType: contentType,
      );
      
      // Create string to sign
      final stringToSign = _createStringToSign(
        timestamp: timestamp,
        canonicalRequest: canonicalRequest,
      );
      
      // Calculate signature
      final signature = _calculateSignature(
        dateStamp: dateStamp,
        stringToSign: stringToSign,
      );
      
      // Create authorization header
      final signedHeadersList = canonicalRequest.split('\n')[4]; // Extract signed headers from canonical request
      final authHeader = _createAuthorizationHeader(
        dateStamp: dateStamp,
        signature: signature,
        signedHeaders: signedHeadersList,
      );
      
      // Make the request
      final request = http.Request('PUT', Uri.parse(url));
      request.headers['Authorization'] = authHeader;
      request.headers['x-amz-date'] = amzDate;
      request.headers['x-amz-content-sha256'] = _sha256Hash(fileBytes);
      if (contentType != null) {
        request.headers['content-type'] = contentType;
      }
      request.bodyBytes = fileBytes;
      
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        // Return the public URL
        return '$_endpoint/$bucket/$fileName';
      } else {
        throw Exception('Failed to upload file: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception('Error uploading file to R2: $e');
    }
  }

  /// Delete file from Cloudflare R2
  Future<void> deleteFile(String bucket, String fileName) async {
    try {
      final url = '$_endpoint/$bucket/$fileName';
      final timestamp = DateTime.now().toUtc();
      final dateStamp = _formatDateStamp(timestamp);
      final amzDate = _formatAmzDate(timestamp);
      
      // Create canonical request for DELETE
      final canonicalRequest = _createCanonicalRequest(
        method: 'DELETE',
        path: '/$bucket/$fileName',
        host: Uri.parse(_endpoint).host,
        amzDate: amzDate,
        payloadHash: _sha256Hash(Uint8List(0)),
      );
      
      // Create string to sign
      final stringToSign = _createStringToSign(
        timestamp: timestamp,
        canonicalRequest: canonicalRequest,
      );
      
      // Calculate signature
      final signature = _calculateSignature(
        dateStamp: dateStamp,
        stringToSign: stringToSign,
      );
      
      // Create authorization header
      final signedHeadersList = canonicalRequest.split('\n')[4]; // Extract signed headers from canonical request
      final authHeader = _createAuthorizationHeader(
        dateStamp: dateStamp,
        signature: signature,
        signedHeaders: signedHeadersList,
      );
      
      // Make the DELETE request
      final emptyPayloadHash = _sha256Hash(Uint8List(0));
      final headers = {
        'Authorization': authHeader,
        'x-amz-date': amzDate,
        'x-amz-content-sha256': emptyPayloadHash,
      };
      
      final response = await http.delete(
        Uri.parse(url),
        headers: headers,
      );
      
      if (response.statusCode != 204 && response.statusCode != 200) {
        throw Exception('Failed to delete file: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      throw Exception('Error deleting file from R2: $e');
    }
  }

  /// Get public URL for a file
  String getPublicUrl(String bucket, String fileName) {
    return '$_endpoint/$bucket/$fileName';
  }

  // AWS Signature Version 4 implementation helpers
  
  String _formatDateStamp(DateTime timestamp) {
    return '${timestamp.year.toString().padLeft(4, '0')}'
        '${timestamp.month.toString().padLeft(2, '0')}'
        '${timestamp.day.toString().padLeft(2, '0')}';
  }
  
  String _formatAmzDate(DateTime timestamp) {
    return '${_formatDateStamp(timestamp)}T'
        '${timestamp.hour.toString().padLeft(2, '0')}'
        '${timestamp.minute.toString().padLeft(2, '0')}'
        '${timestamp.second.toString().padLeft(2, '0')}Z';
  }
  
  String _sha256Hash(Uint8List data) {
    return sha256.convert(data).toString();
  }
  
  String _createCanonicalRequest({
    required String method,
    required String path,
    required String host,
    required String amzDate,
    required String payloadHash,
    String? contentType,
  }) {
    // Build canonical headers - must be in alphabetical order
    String canonicalHeaders;
    String signedHeaders;
    
    if (contentType != null) {
      canonicalHeaders = 'content-type:$contentType\n'
          'host:$host\n'
          'x-amz-content-sha256:$payloadHash\n'
          'x-amz-date:$amzDate\n';
      signedHeaders = 'content-type;host;x-amz-content-sha256;x-amz-date';
    } else {
      canonicalHeaders = 'host:$host\n'
          'x-amz-content-sha256:$payloadHash\n'
          'x-amz-date:$amzDate\n';
      signedHeaders = 'host;x-amz-content-sha256;x-amz-date';
    }
    
    return '$method\n'
        '$path\n'
        '\n'  // Query string (empty)
        '$canonicalHeaders\n'
        '$signedHeaders\n'
        '$payloadHash';
  }
  
  String _createStringToSign({
    required DateTime timestamp,
    required String canonicalRequest,
  }) {
    final dateStamp = _formatDateStamp(timestamp);
    final amzDate = _formatAmzDate(timestamp);
    final credentialScope = '$dateStamp/$_region/s3/aws4_request';
    
    return 'AWS4-HMAC-SHA256\n'
        '$amzDate\n'
        '$credentialScope\n'
        '${_sha256Hash(utf8.encode(canonicalRequest))}';
  }
  
  String _calculateSignature({
    required String dateStamp,
    required String stringToSign,
  }) {
    final kDate = _hmacSha256(utf8.encode('AWS4$_secretAccessKey'), dateStamp);
    final kRegion = _hmacSha256(kDate, _region);
    final kService = _hmacSha256(kRegion, 's3');
    final kSigning = _hmacSha256(kService, 'aws4_request');
    final signature = _hmacSha256(kSigning, stringToSign);
    
    return signature.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
  
  List<int> _hmacSha256(List<int> key, String data) {
    final hmac = Hmac(sha256, key);
    return hmac.convert(utf8.encode(data)).bytes;
  }
  
  String _createAuthorizationHeader({
    required String dateStamp,
    required String signature,
    required String signedHeaders,
  }) {
    final credentialScope = '$dateStamp/$_region/s3/aws4_request';
    final credential = '$_accessKeyId/$credentialScope';
    
    return 'AWS4-HMAC-SHA256 '
        'Credential=$credential, '
        'SignedHeaders=$signedHeaders, '
        'Signature=$signature';
  }
}