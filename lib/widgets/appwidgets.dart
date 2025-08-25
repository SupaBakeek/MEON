import 'package:flutter/material.dart';

// ==================== MORSE HISTORY ITEM CLASS ====================
class MorseHistoryItem {
  final String signal;
  final DateTime timestamp;
  final String? senderName;

  MorseHistoryItem({
    required this.signal,
    required this.timestamp,
    this.senderName,
  });
}

// ==================== REUSABLE WIDGETS ====================

class AppWidgets {
  // ==================== CONTAINER DECORATIONS ====================

  static BoxDecoration historyContainerDecoration({
    required Color backgroundColor,
    required Color borderColor,
  }) {
    return BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: borderColor, width: 1),
    );
  }

  static BoxDecoration signalItemDecoration({
    required Color backgroundColor,
    required Color borderColor,
  }) {
    return BoxDecoration(
      color: backgroundColor,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: borderColor, width: 1),
    );
  }

  static BoxDecoration mainContainerDecoration({
    required Color backgroundColor,
  }) {
    return BoxDecoration(
      color: backgroundColor,
      borderRadius: const BorderRadius.all(Radius.circular(25)),
      boxShadow: const [
        BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, 5)),
      ],
    );
  }

  // ==================== HISTORY SECTION HEADER ====================

  static Widget historyHeader({
    required IconData icon,
    required String title,
    required Color color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          title,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  // ==================== EMPTY HISTORY MESSAGE ====================

  static Widget emptyHistoryMessage({
    required String text,
    required Color color,
  }) {
    return Text(
      text,
      style: TextStyle(fontSize: 12, color: color, fontStyle: FontStyle.italic),
    );
  }

  // ==================== SIGNAL ITEM WIDGETS ====================

  static Widget sentSignalItem({
    required MorseHistoryItem item,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: signalItemDecoration(
          backgroundColor: Colors.teal[100]!,
          borderColor: Colors.teal[300]!,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item.signal,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.teal[800],
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${item.timestamp.hour.toString().padLeft(2, '0')}:${item.timestamp.minute.toString().padLeft(2, '0')}',
              style: TextStyle(fontSize: 10, color: Colors.teal[600]),
            ),
          ],
        ),
      ),
    );
  }

  static Widget receivedSignalItem({
    required MorseHistoryItem item,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: signalItemDecoration(
          backgroundColor: Colors.blue[100]!,
          borderColor: Colors.blue[300]!,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.signal,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.blue[800],
              ),
            ),
            if (item.senderName != null)
              Text(
                'From: ${item.senderName}',
                style: TextStyle(fontSize: 10, color: Colors.blue[600]),
              ),
            Text(
              '${item.timestamp.hour.toString().padLeft(2, '0')}:${item.timestamp.minute.toString().padLeft(2, '0')}',
              style: TextStyle(fontSize: 10, color: Colors.blue[600]),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== HISTORY CONTAINERS ====================

  static Widget sentHistoryContainer({
    required List<MorseHistoryItem> sentHistory,
    required String receiverName,
    required Function(int) onDeleteSent,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: historyContainerDecoration(
        backgroundColor: Colors.teal[50]!,
        borderColor: Colors.teal[200]!,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          historyHeader(
            icon: Icons.send,
            title: 'Sent to: $receiverName',
            color: Colors.teal[700]!,
          ),
          const SizedBox(height: 4),
          sentHistory.isEmpty
              ? emptyHistoryMessage(
                  text: 'No signals sent yet',
                  color: Colors.teal[600]!,
                )
              : Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: sentHistory.reversed.map((item) {
                    final index = sentHistory.indexOf(item);
                    return sentSignalItem(
                      item: item,
                      onTap: () => onDeleteSent(index),
                    );
                  }).toList(),
                ),
        ],
      ),
    );
  }

  static Widget receivedHistoryContainer({
    required List<MorseHistoryItem> receivedHistory,
    required Function(int) onDeleteReceived,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: historyContainerDecoration(
        backgroundColor: Colors.blue[50]!,
        borderColor: Colors.blue[200]!,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          historyHeader(
            icon: Icons.call_received,
            title: 'Received:',
            color: Colors.blue[700]!,
          ),
          const SizedBox(height: 4),
          receivedHistory.isEmpty
              ? emptyHistoryMessage(
                  text: 'No signals received yet',
                  color: Colors.blue[600]!,
                )
              : Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: receivedHistory.reversed.map((item) {
                    final index = receivedHistory.indexOf(item);
                    return receivedSignalItem(
                      item: item,
                      onTap: () => onDeleteReceived(index),
                    );
                  }).toList(),
                ),
        ],
      ),
    );
  }

  // ==================== PROGRESS INDICATOR ====================

  static Widget progressIndicator({
    required double progress,
    required bool isHolding,
    Color? activeColor,
    Color? backgroundColor,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Stack(
        children: [
          // Main progress bar
          LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: backgroundColor ?? Colors.grey[300],
            valueColor: AlwaysStoppedAnimation<Color>(
              activeColor ??
                  (isHolding ? Colors.blue[600]! : Colors.blue[400]!),
            ),
          ),
          // Tick markers at 1s and 3s
          Positioned.fill(
            child: Row(
              children: [
                Expanded(flex: 1000, child: Container()),
                Container(width: 2, height: 8, color: Colors.grey[600]),
                Expanded(flex: 2000, child: Container()),
                Container(width: 2, height: 8, color: Colors.grey[800]),
                Expanded(flex: 3000, child: Container()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== CUSTOM CHECKBOX ====================

  static Widget customCheckbox({
    required bool isChecked,
    required VoidCallback onTap,
    Color? checkedColor,
    Color? uncheckedBorderColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: isChecked
              ? (checkedColor ?? Colors.blue[700])
              : Colors.transparent,
          border: Border.all(
            color: isChecked
                ? (checkedColor ?? Colors.blue[700]!)
                : (uncheckedBorderColor ?? Colors.grey[800]!),
            width: 2,
          ),
          borderRadius: BorderRadius.circular(4),
          boxShadow: isChecked
              ? [
                  BoxShadow(
                    color: (checkedColor ?? Colors.teal).withOpacity(0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Icon(
            Icons.check,
            size: 14,
            color: isChecked ? Colors.white : Colors.transparent,
          ),
        ),
      ),
    );
  }

  // ==================== MAIN CONTAINER WITH CHECKBOX ====================

  static Widget mainContainerWithCheckbox({
    required Widget child,
    required Color backgroundColor,
    required bool isChecked,
    required VoidCallback onCheckboxTap,
    Color? checkboxColor,
    Color? checkboxUncheckedBorderColor,
  }) {
    return Stack(
      children: [
        Container(
          width: 250,
          height: 210,
          padding: const EdgeInsets.all(30),
          decoration: mainContainerDecoration(backgroundColor: backgroundColor),
          child: child,
        ),
        Positioned(
          top: 20,
          right: 20,
          child: customCheckbox(
            isChecked: isChecked,
            onTap: onCheckboxTap,
            checkedColor: checkboxColor,
            uncheckedBorderColor: checkboxUncheckedBorderColor,
          ),
        ),
      ],
    );
  }

  // ==================== MAIN BUTTON ====================

  static Widget mainButton({
    required String text,
    required VoidCallback? onPressed,
    required Color backgroundColor,
    bool isElevated = false,
    bool isEnabled = true,
    VoidCallback? onTapDown,
    VoidCallback? onTapUp,
    VoidCallback? onTapCancel,
  }) {
    final bool hasGestureHandlers = onTapDown != null || onTapUp != null || onTapCancel != null;
    final bool isActuallyEnabled = isEnabled && (onPressed != null || hasGestureHandlers);
    
    Widget button = MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: onTapDown != null ? (_) => onTapDown() : null,
        onTapUp: onTapUp != null ? (_) => onTapUp() : null,
        onTapCancel: onTapCancel,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            color: isEnabled ? backgroundColor : Colors.grey[400],
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: isElevated ? 8 : 4,
                offset: Offset(0, isElevated ? 4 : 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: hasGestureHandlers ? null : onPressed,
              borderRadius: BorderRadius.circular(30),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 20),
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (!isActuallyEnabled) {
      button = Opacity(opacity: 0.7, child: button);
    }

    return button;
  }

  // ==================== APP BAR ICON BUTTON ====================

  static Widget appBarIconButton({
    required IconData icon,
    required VoidCallback onPressed,
    required Color color,
    String? tooltip,
    double size = 20,
  }) {
    return IconButton(
      icon: Icon(icon, color: color, size: size),
      tooltip: tooltip,
      onPressed: onPressed,
    );
  }

  // ==================== OUTLINED SELECT BUTTON ====================

  static Widget textButton({
    required String text,
    required VoidCallback onPressed,
    Color? textColor,
  }) {
    return TextButton(
      onPressed: onPressed,
      child: Text(text, style: TextStyle(color: textColor ?? Colors.grey[600])),
    );
  }



  // ==================== FIXED HEIGHT ANIMATED CONTAINER ====================

  static Widget fixedHeightAnimatedContainer({
    required Widget child,
    required bool showContent,
    double height = 80,
  }) {
    return SizedBox(
      height: height,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: showContent ? 1.0 : 0.0,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
          child: child,
        ),
      ),
    );
  }

  // ==================== ------------------------------- ====================
  // ==================== ------------------------------- ====================
  // ==================== ------------------------------- ====================
  // ==================== ------------------------------- ====================
}
