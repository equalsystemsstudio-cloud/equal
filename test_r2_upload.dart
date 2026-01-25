// ignore_for_file: avoid_print
import 'dart:typed_data';
import 'dart:io';
import 'lib/services/cloudflare_r2_service.dart';

void main() async {
  print('Testing Cloudflare R2 Upload...');
  
  try {
    final r2Service = CloudflareR2Service();
    
    // Create a simple test image (1x1 pixel PNG)
    final testImageBytes = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
      0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR chunk
      0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1x1 dimensions
      0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
      0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, // IDAT chunk
      0x54, 0x08, 0x99, 0x01, 0x01, 0x00, 0x00, 0x00,
      0xFF, 0xFF, 0x00, 0x00, 0x00, 0x02, 0x00, 0x01,
      0xE2, 0x21, 0xBC, 0x33, 0x00, 0x00, 0x00, 0x00, // IEND chunk
      0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
    ]);
    
    print('Test image size: ${testImageBytes.length} bytes');
    
    // Test upload to post-images bucket
    final fileName = 'test_${DateTime.now().millisecondsSinceEpoch}.png';
    print('Uploading test file: $fileName');
    
    final publicUrl = await r2Service.uploadFile(
      bucket: CloudflareR2Service.postImagesBucket,
      fileName: 'test_user/$fileName',
      fileBytes: testImageBytes,
      contentType: 'image/png',
    );
    
    print('✅ Upload successful!');
    print('Public URL: $publicUrl');
    
    // Test if the file is accessible
    print('\nTesting file accessibility...');
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse(publicUrl));
    final response = await request.close();
    
    print('HTTP Status: ${response.statusCode}');
    if (response.statusCode == 200) {
      print('✅ File is publicly accessible!');
    } else {
      print('❌ File is not accessible');
    }
    
    client.close();
    
  } catch (e) {
    print('❌ Upload failed with error:');
    print('Error: $e');
    print('Error type: ${e.runtimeType}');
    
    // Check for specific error types
    final errorString = e.toString().toLowerCase();
    if (errorString.contains('403') || errorString.contains('forbidden')) {
      print('\n🔍 Diagnosis: Access denied - Check R2 credentials and permissions');
    } else if (errorString.contains('404') || errorString.contains('not found')) {
      print('\n🔍 Diagnosis: Bucket not found - Check if R2 bucket exists');
    } else if (errorString.contains('network') || errorString.contains('connection')) {
      print('\n🔍 Diagnosis: Network issue - Check internet connection');
    } else if (errorString.contains('signature')) {
      print('\n🔍 Diagnosis: Authentication issue - Check R2 credentials');
    } else {
      print('\n🔍 Diagnosis: Unknown error - Check R2 service configuration');
    }
  }
  
  print('\nTest completed.');
}