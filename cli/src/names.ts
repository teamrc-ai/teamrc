import { randomBytes } from "node:crypto";

/** Curated word list: short, memorable, easy to type. Mix of colors, animals,
 *  materials, nature, and abstract terms. All 3-7 characters. */
const WORDS = [
  // colors
  "coral", "amber", "slate", "ivory", "jade", "ruby", "onyx", "pearl",
  "azure", "crimson", "bronze", "cobalt", "copper", "silver", "gold",
  // animals
  "falcon", "otter", "raven", "lynx", "heron", "viper", "crane", "bison",
  "marten", "osprey", "puma", "wolf", "hawk", "fox", "elk",
  // materials/nature
  "cedar", "flint", "maple", "oak", "pine", "birch", "iron", "stone",
  "ember", "frost", "dusk", "dawn", "ridge", "brook", "cove",
  "cliff", "reef", "mesa", "vale", "glen", "peak", "sage",
  // tech/abstract
  "spark", "pulse", "drift", "flux", "glyph", "prism", "nexus", "arc",
  "bolt", "core", "edge", "node", "mesh", "beam", "ray",
  // more nature
  "moss", "fern", "thorn", "ash", "elm", "ivy", "bay",
  "dune", "tide", "gale", "mist", "haze", "snow", "rain",
  // misc memorable
  "pixel", "quartz", "zinc", "nova", "echo", "delta", "sigma",
  "omega", "theta", "kappa", "zeta",
];

/** Generate a Heroku-style suffix: `<word>-<4hex>` (e.g. `coral-9f3a`). */
export function generateTeamSuffix(): string {
  const word = WORDS[randomBytes(2).readUInt16BE(0) % WORDS.length];
  const hex = randomBytes(2).toString("hex");
  return `${word}-${hex}`;
}

/** Generate a unique team name from a base: `<base>-<word>-<4hex>`. */
export function generateTeamName(baseName: string): string {
  return `${baseName}-${generateTeamSuffix()}`;
}
