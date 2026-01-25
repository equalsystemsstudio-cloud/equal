import 'package:flutter/material.dart';
import '../services/posts_service.dart';
import '../models/post_model.dart';
import 'post_detail_screen.dart';

class PostDetailWrapper extends StatelessWidget {
  final String postId;
  const PostDetailWrapper({super.key, required this.postId});

  @override
  Widget build(BuildContext context) {
    final postsService = PostsService();
    return FutureBuilder<PostModel?>(
      future: postsService.getPostById(postId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Colors.black,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: Center(
              child: Text(
                'Failed to load post',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          );
        }
        final post = snapshot.data;
        if (post == null) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: const Center(
              child: Text(
                'Post not found',
                style: TextStyle(color: Colors.white),
              ),
            ),
          );
        }
        return PostDetailScreen(post: post);
      },
    );
  }
}