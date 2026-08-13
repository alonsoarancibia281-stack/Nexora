import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/pulse_news_desk.dart';

/// Fetches Bitcoin headlines from several public feeds.
///
/// Every source is optional: the desk keeps working with whatever answers in
/// time, and falls back to the last cached batch when the network is down, so
/// a dead feed can never take the prediction screen with it.
class CryptoNewsService {
  CryptoNewsService({http.Client? client}) : _client = client;

  final http.Client? _client;

  static const _cacheKey = 'nexora_news_cache_v1';
  static const _cacheStampKey = 'nexora_news_cache_at_v1';

  static const _cryptoCompare =
      'https://min-api.cryptocompare.com/data/v2/news/?lang=EN&categories=BTC,Blockchain,Trading';
  static const _rssFeeds = <String, String>{
    'Cointelegraph': 'https://cointelegraph.com/rss/tag/bitcoin',
    'CoinDesk': 'https://www.coindesk.com/arc/outboundfeeds/rss/',
    'Bitcoin Magazine': 'https://bitcoinmagazine.com/.rss/full/',
  };

  Future<List<NewsItem>> loadBitcoinNews({int limit = 90}) async {
    final client = _client ?? http.Client();
    final collected = <NewsItem>[];
    try {
      final results = await Future.wait<List<NewsItem>>([
        _loadCryptoCompare(client),
        for (final entry in _rssFeeds.entries)
          _loadRss(client, entry.key, entry.value),
      ]);
      for (final batch in results) {
        collected.addAll(batch);
      }
    } catch (_) {
      // Individual sources already swallow their own failures.
    } finally {
      if (_client == null) client.close();
    }

    final merged = _dedupe(collected);
    if (merged.isNotEmpty) {
      merged.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
      final capped = merged.take(limit).toList(growable: false);
      await _cache(capped);
      return capped;
    }
    return _readCache(limit);
  }

  Future<List<NewsItem>> _loadCryptoCompare(http.Client client) async {
    try {
      final response = await client
          .get(Uri.parse(_cryptoCompare))
          .timeout(const Duration(seconds: 9));
      if (response.statusCode != 200) return const <NewsItem>[];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final rows = data['Data'];
      if (rows is! List) return const <NewsItem>[];
      final items = <NewsItem>[];
      for (final raw in rows) {
        if (raw is! Map<String, dynamic>) continue;
        final published = (raw['published_on'] as num?)?.toInt();
        final title = '${raw['title'] ?? ''}'.trim();
        if (title.isEmpty || published == null) continue;
        items.add(NewsItem(
          title: title,
          body: '${raw['body'] ?? ''}'.trim(),
          source: '${(raw['source_info'] as Map?)?['name'] ?? raw['source'] ?? 'CryptoCompare'}',
          publishedAt:
              DateTime.fromMillisecondsSinceEpoch(published * 1000, isUtc: true),
          categories: '${raw['categories'] ?? ''}',
        ));
      }
      return items;
    } catch (_) {
      return const <NewsItem>[];
    }
  }

  Future<List<NewsItem>> _loadRss(
    http.Client client,
    String source,
    String url,
  ) async {
    try {
      final response = await client.get(
        Uri.parse(url),
        headers: const {'user-agent': 'NexoraMarketsAI/1.0 (+news-desk)'},
      ).timeout(const Duration(seconds: 9));
      if (response.statusCode != 200) return const <NewsItem>[];
      return parseRss(response.body, source);
    } catch (_) {
      return const <NewsItem>[];
    }
  }

  /// Minimal RSS/Atom reader. Kept dependency-free on purpose: the desk only
  /// needs title, description and timestamp.
  static List<NewsItem> parseRss(String xml, String source) {
    final items = <NewsItem>[];
    final entryPattern = RegExp(r'<(item|entry)\b[\s\S]*?</\1>', multiLine: true);
    for (final match in entryPattern.allMatches(xml)) {
      final block = match.group(0) ?? '';
      final title = _extractTag(block, 'title');
      if (title.isEmpty) continue;
      final description = _extractTag(block, 'description').isNotEmpty
          ? _extractTag(block, 'description')
          : _extractTag(block, 'summary');
      final dateText = [
        _extractTag(block, 'pubDate'),
        _extractTag(block, 'updated'),
        _extractTag(block, 'published'),
        _extractTag(block, 'dc:date'),
      ].firstWhere((v) => v.isNotEmpty, orElse: () => '');
      final published = _parseDate(dateText) ?? DateTime.now().toUtc();
      items.add(NewsItem(
        title: title,
        body: description,
        source: source,
        publishedAt: published,
        categories: _extractTag(block, 'category'),
      ));
    }
    return items;
  }

  static String _extractTag(String block, String tag) {
    final pattern = RegExp('<$tag\\b[^>]*>([\\s\\S]*?)</$tag>');
    final match = pattern.firstMatch(block);
    if (match == null) return '';
    var value = match.group(1) ?? '';
    value = value.replaceAll(RegExp(r'<!\[CDATA\[|\]\]>'), '');
    value = value.replaceAll(RegExp(r'<[^>]+>'), ' ');
    value = value
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ');
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static DateTime? _parseDate(String value) {
    if (value.isEmpty) return null;
    final iso = DateTime.tryParse(value);
    if (iso != null) return iso.toUtc();
    // RFC 822, e.g. "Wed, 13 Aug 2026 10:24:00 GMT".
    final match = RegExp(
      r'(\d{1,2})\s+([A-Za-z]{3})\s+(\d{4})\s+(\d{2}):(\d{2})(?::(\d{2}))?',
    ).firstMatch(value);
    if (match == null) return null;
    const months = <String, int>{
      'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
      'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
    };
    final month = months[match.group(2)!.toLowerCase()];
    if (month == null) return null;
    return DateTime.utc(
      int.parse(match.group(3)!),
      month,
      int.parse(match.group(1)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
      int.parse(match.group(6) ?? '0'),
    );
  }

  static List<NewsItem> _dedupe(List<NewsItem> items) {
    final seen = <String>{};
    final out = <NewsItem>[];
    for (final item in items) {
      final key = item.title
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (key.isEmpty || !seen.add(key)) continue;
      out.add(item);
    }
    return out;
  }

  Future<void> _cache(List<NewsItem> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _cacheKey,
        jsonEncode([for (final i in items.take(60)) i.toJson()]),
      );
      await prefs.setInt(
        _cacheStampKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    } catch (_) {
      // Cache is best effort.
    }
  }

  Future<List<NewsItem>> _readCache(int limit) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return const <NewsItem>[];
      final rows = jsonDecode(raw) as List<dynamic>;
      final items = <NewsItem>[];
      for (final row in rows) {
        final item = NewsItem.fromJson(row as Map<String, dynamic>);
        if (item != null) items.add(item);
      }
      return items.take(limit).toList(growable: false);
    } catch (_) {
      return const <NewsItem>[];
    }
  }
}
