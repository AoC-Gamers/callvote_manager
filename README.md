# Call Vote Manager
[EN] [translation](https://translate.google.com/translate?sl=es&tl=en&u=https://github.com/lechuga16/callvote_manager)

Este complemento modular para Left 4 Dead 2 permite una administración eficiente de llamadas a votaciones.

## Call Vote Manager
- El complemento principal para gestionar las votaciones. Permite aprobar o denegar votaciones según las preferencias del servidor.
- Cuenta con funciones nativas para cancelar votaciones.
- Registra todas las llamadas a votaciones, ya sea de forma local o a través de una base de datos SQL.
- Convar relacionadas por votaciones serán administradas por este complemento.
- Proporciona inmunidad a las votaciones de expulsión para los roles de administrador y VIP.
- Ofrece anuncios de votaciones con opciones de traducción.
- Permite realizar un seguimiento de las votaciones de manera directa o anónima.

## Call Vote Kick Limit
- Un módulo adicional que registra las votaciones de expulsión (VoteKick) y limita su uso en caso de abuso o exceso.
- El contador de expulsiones se puede integrar con una base de datos o mantener localmente en el servidor.
- Proporciona comandos para mostrar la cantidad de expulsiones por jugador y en general.
- Emite anuncios sobre el progreso de las votaciones, con opciones para mantener el anonimato si así se prefiere.
- 
## SQL
- La config guardada en database.cfg debe tener de título "callvote"
- Para crear las tablas, se debe ejecutar el comando respectivo de cada complemento.
