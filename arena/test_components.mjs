import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { finish, init, step } from './game/ctf_game.js';
import { onMessage, start } from './player/ctf_player_baseline.js';
import { replayChunks, resultBody } from './test_host_output.mjs';

const ffaMode = process.argv[2] === 'ffa';
const seed = 0xfedcba9876543210n;
const seats = ffaMode ? 12 : 2;
const ticks = ffaMode ? 8641 : 13;
const config = ffaMode
  ? readFileSync(process.env.FFA_CONFIG, 'utf8')
  : JSON.stringify({
    players: [{ name: 'alpha' }, { name: 'beta' }],
    minPlayers: 2,
    maxTicks: 12,
    maxGames: 1,
  });
const scriptedMask = (seat, tick) => [8, 0, 4, 0, 16, 0][
  (tick + seat) % 6
];
const playerMasks = [];
let completed = false;

init(config, seats, seed);
start(0, undefined);
for (let tick = 0; tick < ticks; tick += 1) {
  const output = step(Array.from({ length: seats }, (_, seat) => ({
    seat,
    payload: Uint8Array.of(
      0x84,
      ffaMode
        ? scriptedMask(seat, tick)
        : (seat === 0 ? [8, 8, 0, 16, 0, 2] : [4, 4, 0, 32, 0, 1])[
          tick % 6
      ],
    ),
  })));
  if (output.done) {
    assert(ffaMode || tick === ticks - 1);
  }
  assert.equal(output.messages.length, seats);
  const replies = onMessage(output.messages[0].payload);
  playerMasks.push(replies.length === 0 ? -1 : replies[0][1]);
  if (replies.length > 0) {
    assert.equal(replies.length, 1);
    assert.equal(replies[0][0], 0x84);
  }
  if (output.done) {
    completed = true;
    break;
  }
}
assert(completed);
finish();
assert.throws(() => step([]), /not initialized/);

const componentHashes = replayChunks
  .filter((chunk) => chunk.length === 13 && chunk[0] === 1)
  .map((chunk) => new DataView(
    chunk.buffer,
    chunk.byteOffset,
    chunk.byteLength,
  ).getBigUint64(5, true).toString());
const nativeHashes = readFileSync(process.env.NATIVE_HASHES_FILE, 'utf8').split(',');
assert.equal(componentHashes.length, nativeHashes.length);
assert.deepEqual(componentHashes, nativeHashes);
const results = JSON.parse(new TextDecoder().decode(resultBody));
assert.deepEqual(
  results,
  JSON.parse(readFileSync(process.env.NATIVE_RESULTS_FILE, 'utf8')),
);
assert.deepEqual(
  playerMasks,
  readFileSync(process.env.NATIVE_PLAYER_MASKS_FILE, 'utf8').split(',').map(Number),
);
assert(playerMasks.some((mask) => mask >= 0));
console.log(`native/component parity: ${componentHashes.length} hashes, results, and player masks`);
