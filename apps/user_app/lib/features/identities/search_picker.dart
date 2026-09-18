import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/identity_repository.dart';

/// Full-height search sheet for professions, skills and places.
Future<TaxonomyHit?> showSearchPicker(
  BuildContext context, {
  required String title,
  required String hint,
  required Future<List<TaxonomyHit>> Function(String query) search,
  bool searchWhenEmpty = true,
  String emptyText = 'Nothing found. Try another word.',
}) {
  return showModalBottomSheet<TaxonomyHit>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 700),
    builder: (_) => _SearchSheet(
      title: title,
      hint: hint,
      search: search,
      searchWhenEmpty: searchWhenEmpty,
      emptyText: emptyText,
    ),
  );
}

class _SearchSheet extends StatefulWidget {
  const _SearchSheet({
    required this.title,
    required this.hint,
    required this.search,
    required this.searchWhenEmpty,
    required this.emptyText,
  });

  final String title;
  final String hint;
  final Future<List<TaxonomyHit>> Function(String) search;
  final bool searchWhenEmpty;
  final String emptyText;

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final _ctl = TextEditingController();
  Timer? _debounce;
  List<TaxonomyHit> _hits = const [];
  bool _loading = false;
  String? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    if (widget.searchWhenEmpty) _run('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctl.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(q));
  }

  Future<void> _run(String q) async {
    if (!widget.searchWhenEmpty && q.trim().isEmpty) {
      setState(() => _hits = const []);
      return;
    }
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final hits = await widget.search(q);
      if (!mounted || seq != _seq) return;
      setState(() {
        _hits = hits;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _error = identityError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(widget.title,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _ctl,
                autofocus: true,
                textInputAction: TextInputAction.search,
                style: const TextStyle(fontSize: 16),
                decoration: InputDecoration(
                  hintText: widget.hint,
                  prefixIcon: const Icon(Icons.search),
                ),
                onChanged: _onChanged,
                onSubmitted: _run,
              ),
            ),
            const SizedBox(height: 8),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(_error!,
                            textAlign: TextAlign.center,
                            style: TextStyle(color: scheme.error)),
                      ),
                    )
                  : _hits.isEmpty && !_loading
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _ctl.text.trim().isEmpty && !widget.searchWhenEmpty
                                  ? 'Type to search.'
                                  : widget.emptyText,
                              textAlign: TextAlign.center,
                              style:
                                  TextStyle(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _hits.length,
                          separatorBuilder: (_, __) =>
                              const Divider(indent: 20, endIndent: 20),
                          itemBuilder: (_, i) => ListTile(
                            minTileHeight: 56,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 20),
                            title: Text(_hits[i].name,
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600)),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.pop(context, _hits[i]),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
