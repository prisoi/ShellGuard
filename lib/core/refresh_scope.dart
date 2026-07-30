enum RefreshScope {
  dashboard,
  docker,
  firewall,
  ports,
  processes,
  services,
  files,
}

extension RefreshScopeKey on RefreshScope {
  String get key => name;
}

