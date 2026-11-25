import 'dart:io';
import 'package:flutter/material.dart';
import '../domain/preset.dart';
import '../services/app_state.dart';
import '../services/library.dart';
import '../services/system_gallery.dart';
import 'components.dart';
import 'editor_page.dart';
import 'design_system.dart';
import 'live_photo_view.dart';
import 'share_photo.dart';

class GalleryPage extends StatefulWidget {
  final AppState state;
  const GalleryPage({super.key, required this.state});
  @override
  State<GalleryPage> createState() => _GalleryPageState();
}

class _GalleryPageState extends State<GalleryPage> with WidgetsBindingObserver {
  bool selecting = false, deleting = false;
  final selected = <String>{};
  AppState get app => widget.state;
  @override
  void initState() {
    super.initState();
    app.addListener(changed);
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }

  Future<void> refresh() async {
    if (deleting) return;
    await app.refresh(syncSystem: true);
  }

  Future<void> retryDraft(int id) async {
    try {
      final issue = await app.retryCapture(id);
      if (mounted && issue.isNotEmpty) toast(context, issue);
    } catch (_) {
      if (mounted) toast(context, '照片仍未保存，已保留原图');
    }
  }

  Future<void> discardDraft(int id) async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('放弃这张未保存的照片？'),
        content: const Text('原图和对应的 Live 素材将被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('保留'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) {
      await guarded(context, () => app.discardCapture(id));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !deleting) refresh();
  }

  void changed() {
    if (mounted) {
      setState(() => selected.retainAll(app.photos.map((p) => p.path)));
    }
  }

  void finishSelection() => setState(() {
    selecting = false;
    selected.clear();
  });
  void toggle(PhotoEntry photo) => setState(() {
    selecting = true;
    if (!selected.add(photo.path)) selected.remove(photo.path);
  });

  Future<void> removeSelected() async {
    if (deleting || selected.isEmpty) return;
    final photos = app.photos.where((p) => selected.contains(p.path)).toList();
    setState(() => deleting = true);
    await guarded(context, () async {
      var linkedCount = 0;
      if (app.syncAlbumDeletes) {
        for (final photo in photos) {
          if (await app.albumSync.mayHaveSystemCopy(photo)) linkedCount++;
        }
      }
      if (!mounted) return;
      final localCount = photos.length - linkedCount;
      final yes = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text('删除这 ${photos.length} 张照片？'),
          content: Text(
            [
              if (linkedCount > 0) '其中 $linkedCount 张会核对系统相册并尝试联动删除。',
              if (localCount > 0) '其中 $localCount 张仅从应用内相册删除。',
              '原图和编辑记录也会删除。',
              if (linkedCount > 0) '无法核对或取消系统删除时会保留对应照片。',
            ].join('\n\n'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('保留'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: PandaDesign.danger,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(dialog, true),
              child: Text('删除 ${photos.length} 张'),
            ),
          ],
        ),
      );
      if (yes != true || !mounted) return;
      if (linkedCount > 0 &&
          await app.systemGallery.access() != GalleryAccess.full) {
        final permission = await app.systemGallery.access(request: true);
        if (permission != GalleryAccess.full) {
          if (mounted) toast(context, '相册访问权限不足，照片已保留。');
          return;
        }
      }
      final result = await app.albumSync.removeMany(
        photos,
        linked: app.syncAlbumDeletes,
      );
      await app.refresh();
      if (!mounted) return;
      setState(() {
        selected.removeAll(result.deleted);
        if (selected.isEmpty) selecting = false;
      });
      toast(
        context,
        result.deleted.isEmpty
            ? '照片未删除。请确认相册权限和同步状态后重试。'
            : '已删除 ${result.deleted.length} 张${result.kept.isEmpty ? '' : '，${result.kept.length} 张未删除'}',
      );
    });
    if (mounted) setState(() => deleting = false);
  }

  @override
  void dispose() {
    app.removeListener(changed);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !selecting && !deleting,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && selecting && !deleting) finishSelection();
    },
    child: Scaffold(
      backgroundColor: PandaDesign.background,
      appBar: AppBar(
        backgroundColor: PandaDesign.background,
        leading: selecting
            ? IconButton(
                tooltip: '退出选择',
                onPressed: deleting ? null : finishSelection,
                icon: const Icon(Icons.close),
              )
            : null,
        title: Semantics(
          liveRegion: selecting,
          child: Text(selecting ? '已选 ${selected.length} 张' : '相册'),
        ),
        actions: [
          if (selecting)
            TextButton(
              onPressed: deleting
                  ? null
                  : () => setState(() {
                      if (selected.length == app.photos.length) {
                        selected.clear();
                      } else {
                        selected.addAll(app.photos.map((p) => p.path));
                      }
                    }),
              child: Text(selected.length == app.photos.length ? '取消全选' : '全选'),
            ),
          TextButton(
            onPressed: app.photos.isEmpty || deleting
                ? null
                : () {
                    if (selecting) {
                      finishSelection();
                    } else {
                      setState(() => selecting = true);
                    }
                  },
            child: Text(selecting ? '取消' : '选择'),
          ),
        ],
      ),
      bottomNavigationBar: selecting
          ? SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                decoration: const BoxDecoration(
                  color: PandaDesign.background,
                  border: Border(top: BorderSide(color: PandaDesign.line)),
                ),
                child: Row(
                  children: [
                    const Spacer(),
                    FilledButton.icon(
                      key: const ValueKey('gallery-delete-selected'),
                      onPressed: deleting || selected.isEmpty
                          ? null
                          : removeSelected,
                      style: FilledButton.styleFrom(
                        backgroundColor: PandaDesign.danger,
                        foregroundColor: Colors.white,
                      ),
                      icon: deleting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.delete_outline, size: 20),
                      label: Text(deleting ? '删除中…' : '删除'),
                    ),
                  ],
                ),
              ),
            )
          : null,
      body: SafeArea(
        top: false,
        bottom: !selecting,
        child: RefreshIndicator(
          onRefresh: refresh,
          child: CustomScrollView(
            key: const PageStorageKey('panda-gallery-grid'),
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: galleryContents(),
          ),
        ),
      ),
    ),
  );

  List<Widget> galleryContents() {
    final recovery = [
      if (!selecting)
        for (final draft in app.failedCaptures)
          SliverToBoxAdapter(
            child: ListTile(
              leading: const Icon(Icons.error_outline),
              title: const Text('照片未保存'),
              subtitle: Text(
                MaterialLocalizations.of(
                  context,
                ).formatShortDate(draft.edit.date.toLocal()),
              ),
              trailing: Wrap(
                children: [
                  TextButton(
                    onPressed: app.captureRecoveryBusy(draft.id)
                        ? null
                        : () => discardDraft(draft.id),
                    child: const Text('放弃'),
                  ),
                  TextButton(
                    onPressed: app.captureRecoveryBusy(draft.id)
                        ? null
                        : () => retryDraft(draft.id),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
    ];
    if (app.photos.isEmpty) {
      return [
        ...recovery,
        if (recovery.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.photo_library_outlined, color: ink, size: 34),
                    SizedBox(height: 14),
                    Text('暂无照片', textAlign: TextAlign.center),
                    SizedBox(height: 6),
                    Text(
                      '拍下的照片会出现在这里',
                      style: TextStyle(color: PandaDesign.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ];
    }
    final months = <(int, int), List<PhotoEntry>>{};
    for (final photo in app.photos) {
      final date = photo.date.toLocal();
      (months[(date.year, date.month)] ??= []).add(photo);
    }
    return [
      ...recovery,
      for (final entry in months.entries) ...[
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${entry.key.$1} 年 ${entry.key.$2} 月',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${entry.value.length} 张',
                  style: const TextStyle(
                    fontSize: 12,
                    color: PandaDesign.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          sliver: SliverGrid.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 160,
              mainAxisSpacing: 4,
              crossAxisSpacing: 4,
            ),
            itemCount: entry.value.length,
            itemBuilder: (context, index) => photoTile(entry.value[index]),
          ),
        ),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 20)),
    ];
  }

  Widget photoTile(PhotoEntry photo) {
    final isSelected = selected.contains(photo.path);
    final preset = presets.firstWhere(
      (p) => p.id == photo.preset,
      orElse: () => presets.first,
    );
    return Semantics(
      selected: selecting ? isSelected : null,
      label: '${preset.name}，${photo.date.month}月${photo.date.day}日',
      child: Material(
        key: ValueKey('gallery-photo-${photo.path}'),
        color: PandaDesign.raised,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onLongPress: deleting ? null : () => toggle(photo),
          onTap: deleting
              ? null
              : () async {
                  if (selecting) {
                    toggle(photo);
                    return;
                  }
                  await Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => PhotoPage(
                        state: app,
                        photo: photo,
                        photos: app.photos.toList(),
                      ),
                    ),
                  );
                  if (mounted) await refresh();
                },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(
                File(photo.path),
                fit: BoxFit.cover,
                cacheWidth: 420,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.broken_image_outlined),
              ),
              if (photo.live)
                const Positioned(
                  top: 6,
                  left: 6,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.all(Radius.circular(5)),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        child: Text(
                          'LIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            letterSpacing: .4,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (selecting)
                Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0x29000000)
                            : Colors.transparent,
                        border: isSelected
                            ? Border.all(color: ink, width: 2)
                            : null,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Align(
                        alignment: Alignment.topRight,
                        child: Container(
                          width: 24,
                          height: 24,
                          margin: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: isSelected ? ink : Colors.black38,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white),
                          ),
                          child: isSelected
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 16,
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class PhotoPage extends StatefulWidget {
  final AppState state;
  final PhotoEntry photo;
  final List<PhotoEntry> photos;
  const PhotoPage({
    super.key,
    required this.state,
    required this.photo,
    this.photos = const [],
  });
  @override
  State<PhotoPage> createState() => _PhotoPageState();
}

class _PhotoPageState extends State<PhotoPage> with WidgetsBindingObserver {
  bool busy = false, zoomed = false;
  late List<PhotoEntry> photos;
  late int index;
  late final PageController pages;
  PhotoEntry get photo => photos[index];

  @override
  void initState() {
    super.initState();
    photos = widget.photos.toList();
    index = photos.indexWhere((entry) => entry.path == widget.photo.path);
    if (index < 0) {
      photos.insert(0, widget.photo);
      index = 0;
    }
    pages = PageController(initialPage: index);
    WidgetsBinding.instance.addObserver(this);
  }

  void changePage(int next) {
    if (next == index) return;
    setState(() {
      index = next;
      zoomed = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    pages.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !busy) checkExternalDeletion();
  }

  Future<void> checkExternalDeletion() async {
    await widget.state.refresh(syncSystem: true);
    if (mounted && !busy && ModalRoute.of(context)?.isCurrent == true) {
      reconcilePhotos();
    }
  }

  void reconcilePhotos() {
    final existing = widget.state.photos.map((entry) => entry.path).toSet();
    final remaining = photos
        .where((entry) => existing.contains(entry.path))
        .toList();
    if (remaining.length == photos.length) return;
    if (remaining.isEmpty) {
      Navigator.pop(context);
      return;
    }
    final same = remaining.indexWhere((entry) => entry.path == photo.path);
    final next = same < 0 ? index.clamp(0, remaining.length - 1) : same;
    setState(() {
      photos = remaining;
      index = next;
      zoomed = false;
    });
    if (pages.hasClients) pages.jumpToPage(next);
  }

  Future<void> action(Future<void> Function() fn) async {
    if (busy) return;
    setState(() => busy = true);
    await guarded(context, fn);
    if (mounted) setState(() => busy = false);
  }

  Future<void> remove() => action(() async {
    final entry = photo;
    final syncDeletes = widget.state.syncAlbumDeletes;
    final linked =
        syncDeletes && await widget.state.albumSync.mayHaveSystemCopy(entry);
    if (!mounted) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这张照片？'),
        content: Text(
          linked
              ? '核对系统相册后联动删除。无法确认时会保留照片、原图和编辑记录。'
              : '仅从应用内相册删除这张照片及其原图和编辑记录。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('保留'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(linked ? '同时删除' : '仅从应用内删除'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    if (linked &&
        await widget.state.systemGallery.access() != GalleryAccess.full) {
      await widget.state.systemGallery.access(request: true);
    }
    await widget.state.albumSync.remove(entry, linked: syncDeletes);
    await widget.state.refresh();
    if (mounted) reconcilePhotos();
  });

  Future<void> syncPhoto(PhotoEntry entry) => action(() async {
    final app = widget.state;
    if (entry.live &&
        (await app.library.liveInfo(entry))?['rendered'] != true) {
      if (mounted) toast(context, 'Live 照片尚未生成，暂时无法同步。');
      return;
    }
    final message = await app.albumSync.export(entry);
    if (mounted) toast(context, message);
  });

  Future<void> editPhoto(PhotoEntry entry) => action(() async {
    final original = File(entry.path.replaceAll('.png', '.original'));
    final hasOriginal = await original.exists();
    final bytes = await (hasOriginal ? original : File(entry.path))
        .readAsBytes();
    final edit = hasOriginal
        ? await widget.state.library.readEdit(entry)
        : null;
    final motion = await widget.state.library.liveSource(entry);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => EditorPage(
          state: widget.state,
          bytes: bytes,
          initialEdit: edit,
          initialPreset: entry.preset,
          retainSource: hasOriginal,
          liveSource: motion,
        ),
      ),
    );
  });

  @override
  Widget build(BuildContext context) {
    final entry = photo;
    final date = entry.date.toLocal();
    final preset = presets.firstWhere(
      (p) => p.id == entry.preset,
      orElse: () => presets.first,
    );
    return Scaffold(
      appBar: AppBar(
        title: MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.3,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                photos.length == 1 ? '照片' : '${index + 1} / ${photos.length}',
                semanticsLabel: '第 ${index + 1} 张，共 ${photos.length} 张',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '${date.month}月${date.day}日 · ${preset.compactName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: PandaDesign.muted),
              ),
            ],
          ),
        ),
        actions: [
          FutureBuilder<bool>(
            key: ValueKey(entry.path),
            future: widget.state.albumSync.needsSystemSync(entry),
            builder: (context, snapshot) => snapshot.data == true
                ? IconButton(
                    tooltip: '同步到系统相册',
                    onPressed: busy ? null : () => syncPhoto(entry),
                    icon: const Icon(Icons.sync),
                  )
                : const SizedBox.shrink(),
          ),
          Builder(
            builder: (buttonContext) => IconButton(
              tooltip: '分享照片',
              onPressed: busy
                  ? null
                  : () => action(() => sharePhoto(buttonContext, entry)),
              icon: const Icon(Icons.ios_share),
            ),
          ),
          IconButton(
            tooltip: '再次编辑',
            onPressed: busy ? null : () => editPhoto(entry),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: '删除照片',
            onPressed: busy ? null : remove,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: PageView.builder(
          controller: pages,
          physics: busy || zoomed ? const NeverScrollableScrollPhysics() : null,
          itemCount: photos.length,
          onPageChanged: changePage,
          itemBuilder: (context, position) {
            final entry = photos[position];
            final cover = GalleryPhotoZoom(
              path: entry.path,
              onZoomChanged: (value) {
                if (entry.path == photo.path && value != zoomed) {
                  setState(() => zoomed = value);
                }
              },
            );
            return KeyedSubtree(
              key: ValueKey(entry.path),
              child: entry.live && position == index
                  ? LivePhotoView(app: widget.state, photo: entry, cover: cover)
                  : cover,
            );
          },
        ),
      ),
    );
  }
}
