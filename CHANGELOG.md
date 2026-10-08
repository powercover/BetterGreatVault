# Better Great Vault 1.0.1

- **Escape closes the loot table or loot database first.** The Great Vault stays open behind it;
  a second Escape closes the vault. (In combat, Escape closes both, as the game forbids addons
  to keep a key then.)
- **Smoother reward reveal.** Opening the vault with rewards waiting reads the loot journal in
  one small slice per pass, however many rewards there are, so the opening animations no longer
  stutter the first time in a session.
- **Smoother loot lists while they load.** Rows now move with their items as the list fills
  instead of being repainted, so the row under the pointer keeps its tooltip.
- `/bgv perf` reports what the last reward reveal cost.
