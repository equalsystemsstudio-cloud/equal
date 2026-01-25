import 'package:flutter/material.dart';
import '../services/upload_service.dart';
import '../config/app_colors.dart';

class UploadStatusWidget extends StatelessWidget {
  const UploadStatusWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<UploadStatus>(
      stream: UploadService().statusStream,
      initialData: UploadService().currentStatus,
      builder: (context, snapshot) {
        final status = snapshot.data;
        if (status == null || status.state == UploadState.idle) {
          return const SizedBox.shrink();
        }

        final bool isError = status.state == UploadState.error;
        final bool isSuccess = status.state == UploadState.success;

        return Positioned(
          top: MediaQuery.of(context).padding.top + 10,
          left: 16,
          right: 16,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isError
                    ? Colors.red.withOpacity(0.9)
                    : isSuccess
                        ? Colors.green.withOpacity(0.9)
                        : const Color(0xFF2A2A2A).withOpacity(0.95),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  if (isSuccess)
                    const Icon(Icons.check_circle, color: Colors.white)
                  else if (isError)
                    const Icon(Icons.error, color: Colors.white)
                  else
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        value: status.progress > 0 ? status.progress : null,
                        strokeWidth: 2,
                        valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          status.message,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (status.errorMessage != null)
                          Text(
                            status.errorMessage!,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
