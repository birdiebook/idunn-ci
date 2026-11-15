# Idunn, spegel för CI

Det här repot är en automatisk spegel av koden till en privat iPhone-app. Den finns bara för att köra tester,
kompilera appen och bygga den i GitHub Actions. Utvecklingen sker någon annanstans: här tas inga ärenden och inga pull requests
emot, och historiken är bara speglingarna.

Varje commit är skrivet av `idunn-spegel`. Filen `PRIVAT_COMMIT` säger vilket commit i källan som speglats, och
resultaten läggs på grenen `ci-resultat` under det namnet.

Ingen licens: alla rättigheter förbehålls.
