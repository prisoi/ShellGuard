enum SortDirection { ascending, descending }

class QueryOptions {
  final String keyword;
  final String sortBy;
  final SortDirection direction;
  final Map<String, String> filters;

  const QueryOptions({
    this.keyword = '',
    required this.sortBy,
    this.direction = SortDirection.ascending,
    this.filters = const <String, String>{},
  });

  bool get ascending => direction == SortDirection.ascending;

  QueryOptions copyWith({
    String? keyword,
    String? sortBy,
    SortDirection? direction,
    Map<String, String>? filters,
  }) {
    return QueryOptions(
      keyword: keyword ?? this.keyword,
      sortBy: sortBy ?? this.sortBy,
      direction: direction ?? this.direction,
      filters: filters ?? this.filters,
    );
  }
}
