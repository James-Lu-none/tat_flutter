import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:logger/logger.dart';

import 'ansi_parser.dart';

final ListQueue<OutputEvent> _outputEventBuffer = ListQueue();
int _bufferSize = 50;
bool _initialized = false;

class MyConsoleOutput extends LogOutput {
  @override
  void output(OutputEvent event) {
    if (_outputEventBuffer.length == _bufferSize) {
      _outputEventBuffer.removeFirst();
    }
    _outputEventBuffer.add(event);
  }
}

class LogConsole extends StatefulWidget {
  final bool dark;

  LogConsole({super.key, this.dark = false}) : assert(_initialized, "Please call LogConsole.init() first.");

  static void init({int bufferSize = 50}) {
    if (_initialized) return;
    _bufferSize = bufferSize;
    _initialized = true;
  }

  static String getLog() {
    bool error = false;
    final List<OutputEvent> events = [];
    for (final event in _outputEventBuffer) {
      events.add(event);
    }
    String log = "";
    for (int i = 0; i < events.length; i++) {
      final event = events[i];
      if (event.level == Level.error) {
        error = true;
        log += event.lines.join("\n");
      }
    }
    if (error) {
      log = log.replaceAll("┌───────────────────────────────────────────────────────────", "");
      log = log.replaceAll("└───────────────────────────────────────────────────────────", "");
      log = log.replaceAll("├┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄", "");
      log = log.replaceAll("├", "");
      log = log.replaceAll("│", "");
      return log.substring(0, (log.length > 2000) ? 2000 : log.length);
    } else {
      return "沒有任何錯誤";
    }
  }

  @override
  State<LogConsole> createState() => _LogConsoleState();
}

class RenderedEvent {
  final int id;
  final Level level;
  final TextSpan span;
  final String lowerCaseText;

  const RenderedEvent(
    this.id,
    this.level,
    this.span,
    this.lowerCaseText,
  );
}

class _LogConsoleState extends State<LogConsole> {
  final ListQueue<RenderedEvent> _renderedBuffer = ListQueue();
  final List<RenderedEvent> _filteredBuffer = [];

  final _scrollController = ScrollController();
  final _filterController = TextEditingController();

  Level _filterLevel = Level.trace;
  double _logFontSize = 14;

  int _currentId = 0;
  bool _scrollListenerEnabled = true;
  bool _followBottom = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (!_scrollListenerEnabled) return;
      final scrolledToBottom = _scrollController.offset >= _scrollController.position.maxScrollExtent;
      setState(() {
        _followBottom = scrolledToBottom;
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _renderedBuffer.clear();
    for (final event in _outputEventBuffer) {
      _renderedBuffer.add(_renderEvent(event));
    }
    _refreshFilter();
  }

  void _refreshFilter() {
    final newFilteredBuffer = _renderedBuffer.where((it) {
      final logLevelMatches = it.level.index >= _filterLevel.index;
      if (!logLevelMatches) {
        return false;
      } else if (_filterController.text.isNotEmpty) {
        final filterText = _filterController.text.toLowerCase();
        return it.lowerCaseText.contains(filterText);
      } else {
        return true;
      }
    }).toList();
    setState(() {
      _filteredBuffer.clear();
      _filteredBuffer.addAll(newFilteredBuffer);
    });

    if (_followBottom) {
      Future.delayed(Duration.zero, _scrollToBottom);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Get.back(),
          ),
          title: const Text("Log Console"),
          actions: [
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _outputEventBuffer.clear();
                didChangeDependencies();
              },
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: () {
                setState(() {
                  _logFontSize++;
                });
              },
            ),
            IconButton(
              icon: const Icon(Icons.remove),
              onPressed: () {
                setState(() {
                  _logFontSize--;
                });
              },
            )
          ],
        ),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _buildLogContent(),
              ),
              _buildBottomBar(),
            ],
          ),
        ),
        floatingActionButton: AnimatedOpacity(
          opacity: _followBottom ? 0 : 1,
          duration: const Duration(milliseconds: 150),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 60),
            child: FloatingActionButton(
              mini: true,
              clipBehavior: Clip.antiAlias,
              onPressed: _scrollToBottom,
              child: Icon(
                Icons.arrow_downward,
                color: widget.dark ? Colors.white : Colors.lightBlue[900],
              ),
            ),
          ),
        ),
      );

  Widget _buildLogContent() => Container(
        color: Colors.grey[150],
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: 1600,
            child: ListView.builder(
              shrinkWrap: true,
              controller: _scrollController,
              itemBuilder: (context, index) {
                final logEntry = _filteredBuffer[index];
                return Text.rich(
                  logEntry.span,
                  key: Key(logEntry.id.toString()),
                  style: TextStyle(fontSize: _logFontSize),
                );
              },
              itemCount: _filteredBuffer.length,
            ),
          ),
        ),
      );

  Widget _buildBottomBar() => LogBar(
        dark: widget.dark,
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(
              child: TextField(
                style: const TextStyle(fontSize: 20),
                controller: _filterController,
                onChanged: (s) => _refreshFilter(),
                decoration: const InputDecoration(
                  labelText: "Filter log output",
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 20),
            DropdownButton(
              value: _filterLevel,
              items: const [
                DropdownMenuItem(
                  value: Level.trace,
                  child: Text("Verbose"),
                ),
                DropdownMenuItem(
                  value: Level.debug,
                  child: Text("Debug"),
                ),
                DropdownMenuItem(
                  value: Level.info,
                  child: Text("Info"),
                ),
                DropdownMenuItem(
                  value: Level.warning,
                  child: Text("Warning"),
                ),
                DropdownMenuItem(
                  value: Level.error,
                  child: Text("Error"),
                ),
                DropdownMenuItem(
                  value: Level.fatal,
                  child: Text("WTF"),
                ),
                DropdownMenuItem(
                  value: Level.off,
                  child: Text("Nothing"),
                )
              ],
              onChanged: (value) {
                if (value != null) {
                  _filterLevel = value;
                  _refreshFilter();
                }
              },
            )
          ],
        ),
      );

  void _scrollToBottom() async {
    _scrollListenerEnabled = false;

    setState(() {
      _followBottom = true;
    });

    final scrollPosition = _scrollController.position;
    await _scrollController.animateTo(
      scrollPosition.maxScrollExtent,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
    );

    _scrollListenerEnabled = true;
  }

  RenderedEvent _renderEvent(OutputEvent event) {
    final parser = AnsiParser(widget.dark);
    final text = event.lines.join('\n');
    parser.parse(text);
    return RenderedEvent(
      _currentId++,
      event.level,
      TextSpan(children: parser.spans),
      text.toLowerCase(),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}

class LogBar extends StatelessWidget {
  final bool dark;
  final Widget child;

  const LogBar({
    super.key,
    required this.dark,
    required this.child,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 60,
        child: Container(
          decoration: BoxDecoration(
            boxShadow: [
              if (!dark)
                BoxShadow(
                  color: Colors.grey[400]!,
                  blurRadius: 3,
                ),
            ],
          ),
          child: Material(
            color: dark ? Colors.blueGrey[900] : Colors.white,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(15, 8, 15, 8),
              child: child,
            ),
          ),
        ),
      );
}
