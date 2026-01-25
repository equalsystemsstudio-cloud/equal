// ignore_for_file: avoid_print
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

void main() async {
  print('Testing Cloudflare R2 Bucket Access...');
  
  // R2 Configuration (from cloudflare_r2_service.dart)
  const accessKeyId = '6fcb86e3f11fc8662d215e00adc8a03a';
  const secretAccessKey = '01e7f847d5f608803bbbd206d8b6305f39adcbb2295f3692de6493e23140720d';
  const endpoint = 'https://27e3a9baccd9653e1ade329045460213.r2.cloudflarestorage.com';
  const region = 'auto';
  
  final buckets = [
    'profile-images',
    'post-images', 
    'post-videos',
    'post-audio',
    'thumbnails'
  ];
  
  for (final bucket in buckets) {
    await testBucketAccess(bucket, endpoint, accessKeyId, secretAccessKey, region);
  }
}

Future<void> testBucketAccess(String bucket, String endpoint, String accessKeyId, String secretAccessKey, String region) async {
  try {
    print('\nTesting bucket: $bucket');
    
    // Create a simple HEAD request to check if bucket exists
    final uri = Uri.parse('$endpoint/$bucket/');
    final timestamp = DateTime.now().toUtc();
    final dateStamp = _formatDateStamp(timestamp);
    final amzDate = _formatAmzDate(timestamp);
    
    // Create canonical request for HEAD
    final canonicalRequest = 'HEAD\n'
        '/$bucket/\n'
        '\n'
        'host:${uri.host}\n'
        'x-amz-date:$amzDate\n'
        '\n'
        'host;x-amz-date\n'
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'; // Empty body hash
    
    // Create string to sign
    final credentialScope = '$dateStamp/$region/s3/aws4_request';
    final stringToSign = 'AWS4-HMAC-SHA256\n'
        '$amzDate\n'
        '$credentialScope\n'
        '${sha256.convert(utf8.encode(canonicalRequest)).toString()}';
    
    // Calculate signature
    final kDate = _hmacSha256(utf8.encode('AWS4$secretAccessKey'), dateStamp);
    final kRegion = _hmacSha256(kDate, region);
    final kService = _hmacSha256(kRegion, 's3');
    final kSigning = _hmacSha256(kService, 'aws4_request');
    final signature = _hmacSha256(kSigning, stringToSign);
    final signatureHex = signature.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    
    // Create authorization header
    final credential = '$accessKeyId/$credentialScope';
    final authHeader = 'AWS4-HMAC-SHA256 '
        'Credential=$credential, '
        'SignedHeaders=host;x-amz-date, '
        'Signature=$signatureHex';
    
    // Make HEAD request
    final request = http.Request('HEAD', uri);
    request.headers['Authorization'] = authHeader;
    request.headers['x-amz-date'] = amzDate;
    
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    
    if (response.statusCode == 200) {
      print('✅ Bucket $bucket exists and is accessible');
    } else if (response.statusCode == 404) {
      print('❌ Bucket $bucket does not exist');
    } else if (response.statusCode == 403) {
      print('❌ Bucket $bucket exists but access denied (check permissions)');
    } else {
      print('❌ Bucket $bucket - HTTP ${response.statusCode}: ${response.body}');
    }
    
  } catch (e) {
    print('❌ Error testing bucket $bucket: $e');
  }
}

String _formatDateStamp(DateTime timestamp) {
  return '${timestamp.year.toString().padLeft(4, '0')}'
      '${timestamp.month.toString().padLeft(2, '0')}'
      '${timestamp.day.toString().padLeft(2, '0')}';
}

String _formatAmzDate(DateTime timestamp) {
  return '${timestamp.year.toString().padLeft(4, '0')}'
      '${timestamp.month.toString().padLeft(2, '0')}'
      '${timestamp.day.toString().padLeft(2, '0')}'
      'T'
      '${timestamp.hour.toString().padLeft(2, '0')}'
      '${timestamp.minute.toString().padLeft(2, '0')}'
      '${timestamp.second.toString().padLeft(2, '0')}'
      'Z';
}

List<int> _hmacSha256(List<int> key, String data) {
  final hmac = Hmac(sha256, key);
  return hmac.convert(utf8.encode(data)).bytes;
}