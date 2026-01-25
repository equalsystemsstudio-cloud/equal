// ignore_for_file: avoid_print, unused_local_variable
import 'package:http/http.dart' as http;

void main() async {
  print('Testing R2 Simple Authentication...');
  
  // R2 Configuration (placeholder values; not used directly below)
  const String accessKeyId = '6fcb86e3f11fc8662d215e00adc8a03a';
  const String secretAccessKey = '01e7f847d5f608803bbbd206d8b6305f39adcbb2295f3692de6493e23140720d';
  const String endpoint = 'https://27e3a9baccd9653e1ade329045460213.r2.cloudflarestorage.com';
  const String region = 'auto';
  
  try {
    // Test 1: Simple GET request to list buckets
    print('\n1. Testing bucket listing...');
    final listUrl = endpoint;
    final response = await http.get(Uri.parse(listUrl));
    print('List buckets response: ${response.statusCode}');
    print('Response body: ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}');
    
    // Test 2: Check if specific bucket exists
    print('\n2. Testing specific bucket access...');
    final bucketUrl = '$endpoint/post-images';
    final bucketResponse = await http.get(Uri.parse(bucketUrl));
    print('Bucket access response: ${bucketResponse.statusCode}');
    print('Response body: ${bucketResponse.body.substring(0, bucketResponse.body.length > 200 ? 200 : bucketResponse.body.length)}');
    
    // Test 3: Try a simple HEAD request
    print('\n3. Testing HEAD request...');
    final headResponse = await http.head(Uri.parse(bucketUrl));
    print('HEAD response: ${headResponse.statusCode}');
    print('Headers: ${headResponse.headers}');
    
  } catch (e) {
    print('❌ Error: $e');
  }
  
  print('\n📋 Analysis:');
  print('- If you see 403 Forbidden: Credentials might be invalid');
  print('- If you see 404 Not Found: Bucket might not exist');
  print('- If you see 200 OK: Basic connectivity is working');
  print('- If you see connection errors: Endpoint URL might be wrong');
}