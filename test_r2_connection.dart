// ignore_for_file: avoid_print
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';

void main() async {
  print('Testing Cloudflare R2 Connection...');
  
  // R2 Configuration
  const accessKeyId = '6fcb86e3f11fc8662d215e00adc8a03a';
  const secretAccessKey = '01e7f847d5f608803bbbd206d8b6305f39adcbb2295f3692de6493e23140720d';
  const endpoint = 'https://27e3a9baccd9653e1ade329045460213.r2.cloudflarestorage.com';
  const region = 'auto';
  
  try {
    print('\n1. Testing basic connection to R2 endpoint...');
    
    // Test basic connection
    final basicResponse = await http.get(Uri.parse(endpoint));
    print('Basic GET response: ${basicResponse.statusCode}');
    if (basicResponse.body.isNotEmpty) {
      print('Response body: ${basicResponse.body}');
    }
    
    print('\n2. Testing authenticated LIST buckets request...');
    
    // Create authenticated request to list buckets
    final uri = Uri.parse(endpoint);
    final timestamp = DateTime.now().toUtc();
    final dateStamp = _formatDateStamp(timestamp);
    final amzDate = _formatAmzDate(timestamp);
    
    // Create canonical request for GET /
    final canonicalRequest = 'GET\n'
        '/\n'
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
    
    // Make authenticated GET request
    final request = http.Request('GET', uri);
    request.headers['Authorization'] = authHeader;
    request.headers['x-amz-date'] = amzDate;
    
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    
    print('Authenticated GET response: ${response.statusCode}');
    if (response.body.isNotEmpty) {
      print('Response body: ${response.body}');
    }
    
    print('\n3. Testing with a common bucket name...');
    
    // Test with a simple bucket name that might exist
    final testBuckets = ['equal', 'equal-media', 'media', 'uploads'];
    
    for (final bucketName in testBuckets) {
      final bucketUri = Uri.parse('$endpoint/$bucketName/');
      final bucketRequest = http.Request('HEAD', bucketUri);
      
      // Create new signature for this bucket
      final bucketCanonicalRequest = 'HEAD\n'
          '/$bucketName/\n'
          '\n'
          'host:${bucketUri.host}\n'
          'x-amz-date:$amzDate\n'
          '\n'
          'host;x-amz-date\n'
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
      
      final bucketStringToSign = 'AWS4-HMAC-SHA256\n'
          '$amzDate\n'
          '$credentialScope\n'
          '${sha256.convert(utf8.encode(bucketCanonicalRequest)).toString()}';
      
      final bucketSignature = _hmacSha256(kSigning, bucketStringToSign);
      final bucketSignatureHex = bucketSignature.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      
      final bucketAuthHeader = 'AWS4-HMAC-SHA256 '
          'Credential=$credential, '
          'SignedHeaders=host;x-amz-date, '
          'Signature=$bucketSignatureHex';
      
      bucketRequest.headers['Authorization'] = bucketAuthHeader;
      bucketRequest.headers['x-amz-date'] = amzDate;
      
      final bucketStreamedResponse = await bucketRequest.send();
      final bucketResponse = await http.Response.fromStream(bucketStreamedResponse);
      
      if (bucketResponse.statusCode == 200) {
        print('✅ Found existing bucket: $bucketName');
      } else {
        print('❌ Bucket $bucketName: HTTP ${bucketResponse.statusCode}');
      }
    }
    
  } catch (e) {
    print('❌ Connection test failed: $e');
    print('\n🔍 This suggests:');
    print('1. Invalid R2 credentials');
    print('2. Incorrect R2 endpoint URL');
    print('3. Network connectivity issues');
    print('4. R2 service not properly configured');
  }
  
  print('\n📋 Next Steps:');
  print('1. Verify R2 credentials in Cloudflare dashboard');
  print('2. Create the required buckets in R2');
  print('3. Check R2 CORS and access policies');
  print('4. Ensure R2 service is enabled for your account');
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