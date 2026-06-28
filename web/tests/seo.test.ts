import { describe, expect, it } from 'vitest';
import { jsonLdScript, organizationJsonLd } from '../lib/seo/jsonld';
import { defaultMetadata } from '../lib/seo/metadata';

describe('SEO foundation', () => {
  it('builds the brand Organization entity (GEO anchor)', () => {
    const o = organizationJsonLd();
    expect(o['@type']).toBe('Organization');
    expect(o.name).toBe('Myweli');
    expect(o.areaServed.name).toContain('Ivoire');
  });

  it('serializes valid JSON-LD', () => {
    const parsed = JSON.parse(jsonLdScript(organizationJsonLd()));
    expect(parsed['@context']).toBe('https://schema.org');
  });

  it('default metadata has a title template', () => {
    const title = defaultMetadata.title as { template?: string };
    expect(title.template).toContain('Myweli');
  });
});
