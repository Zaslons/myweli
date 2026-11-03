/// One container, one left edge (docs/design/web-swiss-direction.md §6). The logo,
/// the `<h1>` and the first section start at the same x because they all read this.
/// `/recherche` runs full width, so its header takes the edge without the bound.
export const SITE_EDGE = 'px-m lg:px-l';
export const SITE_CONTAINER = `mx-auto max-w-screen-2xl ${SITE_EDGE}`;
