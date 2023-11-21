part of commits;

class _CommitsController with FilterMixin {
  factory _CommitsController({
    required AzureApiService apiService,
    required StorageService storageService,
    Project? project,
  }) {
    // handle page already in memory with a different project filter
    if (_instances[project.hashCode] != null) {
      return _instances[project.hashCode]!;
    }

    if (instance != null && project?.id != instance!.project?.id) {
      instance = _CommitsController._(apiService, storageService, project);
    }

    instance ??= _CommitsController._(apiService, storageService, project);
    return _instances.putIfAbsent(project.hashCode, () => instance!);
  }

  _CommitsController._(this.apiService, this.storageService, this.project) {
    projectFilter = project ?? projectAll;
  }

  static _CommitsController? instance;
  static final Map<int, _CommitsController> _instances = {};

  final AzureApiService apiService;
  final StorageService storageService;
  final Project? project;

  final recentCommits = ValueNotifier<ApiResponse<List<Commit>?>?>(null);

  void dispose() {
    instance = null;
    _instances.remove(project.hashCode);
  }

  Future<void> init() async {
    await _getData();
  }

  Future<void> _getData() async {
    final res = await apiService.getRecentCommits(
      project: projectFilter.name == projectAll.name ? null : projectFilter,
      author: userFilter.displayName == userAll.displayName ? null : userFilter.mailAddress,
    );
    var commits = (res.data ?? [])..sort((a, b) => b.author!.date!.compareTo(a.author!.date!));

    commits = commits.take(100).toList();

    final projectRepos = groupBy(commits, (c) => '${c.projectId}_${c.repositoryId}');
    final allTags = <TagsData?>[
      ...await Future.wait([
        for (final repoEntry in projectRepos.entries) apiService.getTags(repoEntry.value),
      ]),
    ]..removeWhere((data) => data == null || data.tags.isEmpty);

    if (allTags.isNotEmpty) {
      for (final commit in commits) {
        final repoTags =
            allTags.firstWhereOrNull((t) => t!.projectId == commit.projectId && t.repositoryId == commit.repositoryId);
        commit.tags = repoTags?.tags[commit.commitId];
      }
    }

    recentCommits.value = res.copyWith(data: commits);
  }

  Future<void> goToCommitDetail(Commit commit) async {
    await AppRouter.goToCommitDetail(
      project: commit.projectName,
      repository: commit.repositoryName,
      commitId: commit.commitId!,
    );
  }

  void filterByProject(Project proj) {
    if (proj.id == projectFilter.id) return;

    recentCommits.value = null;
    projectFilter = proj.name! == projectAll.name ? projectAll : proj;
    _getData();
  }

  void filterByUser(GraphUser u) {
    if (u.mailAddress == userFilter.mailAddress) return;

    recentCommits.value = null;
    userFilter = u;
    _getData();
  }

  void resetFilters() {
    recentCommits.value = null;
    projectFilter = projectAll;
    userFilter = userAll;
    init();
  }
}
