final class WatcherFinding {
  const WatcherFinding({
    required this.watcher,
    required this.marker,
    required this.title,
    required this.subjects,
    required this.references,
  });

  final String watcher;
  final String marker;
  final String title;
  final List<String> subjects;
  final List<({String label, String url})> references;

  Map<String, Object> toJson() => <String, Object>{
        'watcher': watcher,
        'marker': marker,
        'title': title,
        'subjects': subjects,
        'references': <Map<String, String>>[
          for (final reference in references)
            <String, String>{
              'label': reference.label,
              'url': reference.url,
            },
        ],
      };
}
