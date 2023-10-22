# Call Vote
[EN] [translation](https://translate.google.com/translate?sl=es&tl=en&u=https://github.com/lechuga16/callvote_manager)

Es un complemento modular que permite la administración de llamadas a votaciones, está enfocado a L4D2.

## Call Vote Manager
- Es el complemento principal, su función es obtener, aprobar o denegar votaciones.
- Nativos para cancelar votaciones.
- Registra las llamadas a votaciones localmente o por sql.
- Convar relacionadas por votaciones serán administradas por este complemento.
- Inmunidad a las votaciones de expulsión (Admin|Vip)
- Anuncios de votaciones con opción a traducción

## Call Vote Kick Limit
- Es un módulo que permite generar un registro de VoteKick y limitar su uso cuando sea excesivo.
- El contador de expulsiones puede apuntar a una base de datos o a la memoria local del servidor.
- Comandos para mostrar la cantidad de kicks por jugador o de todos.

## SQL
- La config guardada en database.cfg debe tener de título "callvote"
- Para crear las tablas, se debe ejecutar el comando respectivo de cada complemento.