# Lot 14 : interface web de démonstration, servie par le serveur de développement de Vite.
# Le contexte de construction est le dossier web/.
FROM node:22-slim
WORKDIR /app

# Les paquets d'abord : Docker garde cette étape en cache tant que la liste ne change pas.
COPY package.json package-lock.json ./
RUN npm ci

COPY . .

EXPOSE 5173
# --host : écouter sur toutes les adresses du conteneur, sinon le navigateur ne peut pas l'atteindre.
CMD ["npm", "run", "dev", "--", "--host", "0.0.0.0"]
