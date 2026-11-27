# Lot 14 : interface web de démonstration, servie par le serveur de développement de Vite.
# Le contexte de construction est le dossier web/.
# Lot 15 : image fixée par tag de version et empreinte (sha256) ; l'interface ne tourne
# plus en administrateur dans son conteneur (comme l'API).
FROM node:26.13.0-slim@sha256:5adad64f9a1fca2d51972caa65983634c8a774eb300d72b20f7f2a0f60368072
WORKDIR /app
RUN chown node:node /app
USER node

# Les paquets d'abord : Docker garde cette étape en cache tant que la liste ne change pas.
COPY --chown=node:node package.json package-lock.json ./
RUN npm ci

COPY --chown=node:node . .

EXPOSE 5173
# --host : écouter sur toutes les adresses du conteneur, sinon le navigateur ne peut pas l'atteindre.
CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0"]
