import { jsonLdScript } from '../lib/seo/jsonld';

/// Emits a JSON-LD `<script>` (SEO/AEO/GEO structured data).
export function JsonLd({ data }: { data: unknown }) {
  return (
    <script
      type="application/ld+json"
      dangerouslySetInnerHTML={{ __html: jsonLdScript(data) }}
    />
  );
}
