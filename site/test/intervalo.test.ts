import assert from 'node:assert/strict';
import { test } from 'node:test';
import { comIntervalo } from '../src/intervalo.ts';

const arquivo = () => new Response(new Uint8Array([0, 1, 2, 3, 4, 5, 6, 7, 8, 9]), { status: 200 });

async function pedir(range: string | null) {
  const res = await comIntervalo(range, arquivo());
  return { status: res.status, faixa: res.headers.get('Content-Range'), bytes: [...new Uint8Array(await res.arrayBuffer())] };
}

test('without Range the whole file comes back and ranges are advertised', async () => {
  const res = await comIntervalo(null, arquivo());
  assert.equal(res.status, 200);
  assert.equal(res.headers.get('Accept-Ranges'), 'bytes');
});

test('answers open, closed and suffix ranges with 206', async () => {
  assert.deepEqual(await pedir('bytes=0-1'), { status: 206, faixa: 'bytes 0-1/10', bytes: [0, 1] });
  assert.deepEqual(await pedir('bytes=7-'), { status: 206, faixa: 'bytes 7-9/10', bytes: [7, 8, 9] });
  assert.deepEqual(await pedir('bytes=-2'), { status: 206, faixa: 'bytes 8-9/10', bytes: [8, 9] });
  assert.deepEqual(await pedir('bytes=8-99'), { status: 206, faixa: 'bytes 8-9/10', bytes: [8, 9] });
});

test('rejects ranges outside the file with 416', async () => {
  assert.equal((await pedir('bytes=10-')).status, 416);
  assert.equal((await pedir('bytes=5-2')).status, 416);
  assert.equal((await pedir('bytes=-')).status, 416);
});

test('ignores range forms it does not support', async () => {
  assert.equal((await pedir('bytes=0-1,4-5')).status, 200);
  assert.equal((await pedir('items=0-1')).status, 200);
});
