-- Sign-ups from the "Quero ajudar" form. No IP and no browser data are stored.
CREATE TABLE inscricoes (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  criado_em TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  nome TEXT NOT NULL,
  email TEXT,
  whatsapp TEXT,
  ajuda TEXT NOT NULL,      -- JSON array of the chosen areas
  cidade TEXT,
  mensagem TEXT,
  politica TEXT NOT NULL    -- version (date) of the privacy notice the person accepted
);

-- Data requests from the privacy page (delete, see, correct); handled by hand.
CREATE TABLE pedidos (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  criado_em TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  contato TEXT NOT NULL,
  mensagem TEXT             -- empty means: delete everything
);
