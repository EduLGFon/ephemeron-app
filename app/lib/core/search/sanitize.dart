// Sanitizes a free-text search query for SQL LIKE by stripping wildcards.
String sanitizeSearch(String q) =>
    q.replaceAll('%', '').replaceAll('_', '').trim();
