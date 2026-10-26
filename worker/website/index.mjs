// The build fills this map from the site's actual HTML documents.
const markdownRoutes = /* @generated-markdown-routes */ {};
const publicData = /* @generated-public-data */ {};

export function prefersMarkdown(accept = '') {
  const types = accept.toLowerCase().split(',').map(part => {
    const [type, ...parameters] = part.trim().split(';');
    const quality = parameters.find(value => value.trim().startsWith('q='));
    const q = quality ? Number(quality.trim().slice(2)) : 1;
    return { type: type.trim(), q: Number.isFinite(q) && q >= 0 && q <= 1 ? q : 0 };
  });
  const markdown = types.find(value => value.type === 'text/markdown')?.q ?? 0;
  const html = types.find(value => value.type === 'text/html')?.q ?? 0;
  return markdown > 0 && markdown >= html;
}

function negotiated(response, request, contentType) {
  const headers = new Headers(response.headers);
  const vary = (headers.get('Vary') || '').split(',').map(value => value.trim()).filter(Boolean);
  if (!vary.some(value => value.toLowerCase() === 'accept')) vary.push('Accept');
  headers.set('Vary', vary.join(', '));
  if (contentType) headers.set('Content-Type', contentType);
  headers.set('X-Content-Type-Options', 'nosniff');
  return new Response(request.method === 'HEAD' ? null : response.body, {
    status: response.status, statusText: response.statusText, headers,
  });
}

function problem(request, status, code, detail) {
  return negotiated(Response.json({
    type: 'about:blank', title: status === 404 ? 'Not Found' : 'Method Not Allowed',
    status, code, detail, instance: new URL(request.url).pathname,
    resolution: 'Read https://vox.isolated.tech/developers for public metadata endpoints, or https://vox.isolated.tech/docs/ for local app integrations. This website has no public capture API.',
  }, { status, headers: status === 405 ? { Allow: 'GET, HEAD' } : {} }), request, 'application/problem+json; charset=utf-8');
}

export function createWebsiteHandler(routes, data = {}) {
  return async function fetch(request, env) {
    const url = new URL(request.url);
    if (!['GET', 'HEAD'].includes(request.method)) {
      return problem(request, 405, 'method_not_allowed', 'This public website supports reading documents with GET or HEAD.');
    }
    if (url.pathname === '/api/v1/product' || url.pathname === '/api/v1/documents') {
      const body = url.pathname.endsWith('/product') ? data.product : { documents: data.documents };
      return negotiated(Response.json(body, { headers: {
        'Cache-Control': 'public, max-age=300', 'Access-Control-Allow-Origin': '*',
      } }), request);
    }
    const markdown = prefersMarkdown(request.headers.get('Accept') || '');
    const markdownPath = Object.hasOwn(routes, url.pathname) ? routes[url.pathname] : undefined;
    if (markdown && markdownPath) {
      const assetURL = new URL(markdownPath, url);
      const asset = await env.ASSETS.fetch(new Request(assetURL, request));
      return negotiated(asset, request, 'text/markdown; charset=utf-8');
    }
    const response = await env.ASSETS.fetch(request);
    if (response.status === 404) {
      if (markdown) {
        return negotiated(new Response('# Page not found\n\nThe requested Vox.md page does not exist. Start with the [homepage](https://vox.isolated.tech/), [documentation](https://vox.isolated.tech/docs/), [sitemap](https://vox.isolated.tech/sitemap.xml), or [agent guide](https://vox.isolated.tech/llms.txt).\n', { status: 404 }), request, 'text/markdown; charset=utf-8');
      }
      if (/^\/api(?:\/|$)/.test(url.pathname) || request.headers.get('Accept')?.includes('application/json')) {
        return problem(request, 404, 'resource_not_found', 'The requested resource does not exist. Vox.md is a local Apple app; this website publishes product information and documentation.');
      }
    }
    return negotiated(response, request);
  };
}

export default { fetch: createWebsiteHandler(markdownRoutes, publicData) };
