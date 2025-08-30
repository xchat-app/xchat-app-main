class IncomingMessage {
  final String id;        // unique id for dedupe
  final String threadId;  // conversation id
  final String title;
  final String? preview;  // preview text
  final bool highPriority;
  final DateTime sentAt;
  IncomingMessage({
    required this.id,
    required this.threadId,
    required this.title,
    this.preview,
    required this.highPriority,
    required this.sentAt,
  });
}

enum PreviewPolicy { hidden, summary, full }