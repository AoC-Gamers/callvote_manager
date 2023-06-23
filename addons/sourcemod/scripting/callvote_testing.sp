#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <colors>
#include <callvotemanager>

/*****************************************************************
			G L O B A L   V A R S
*****************************************************************/

#define PLUGIN_VERSION	   "1.0"
#define MAX_STEAMID_LENGTH 64

/*****************************************************************
			P L U G I N   I N F O
*****************************************************************/

/**
 * Plugin information properties. Plugins can declare a global variable with
 * their info. Example,
 * SourceMod will display this information when a user inspects plugins in the
 * console.
 */
public Plugin myinfo =
{
	name		= "Call Vote Testing",
	author		= "lechuga",
	description = "Performs callvote manager forward testing",
	version		= PLUGIN_VERSION,
	url			= "https://github.com/lechuga16/callvote_manager"
}

/*****************************************************************
			F O R W A R D   P U B L I C S
*****************************************************************/

/**
 * Called when the plugin is fully initialized and all known external references
 * are resolved. This is only called once in the lifetime of the plugin, and is
 * paired with OnPluginEnd().
 *
 * If any run-time error is thrown during this callback, the plugin will be marked
 * as failed.
 */
public void OnPluginStart()
{
	CreateConVar("sm_cvt_version", PLUGIN_VERSION, "Plugin version", FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_SPONLY | FCVAR_DONTRECORD);
}

public void CallVote_Start(int iClient, TypeVotes votes, int iTarget)
{
	// Get the client's SteamID
	char sSteamID[MAX_STEAMID_LENGTH];
	GetClientAuthId(iClient, AuthId_Engine, sSteamID, MAX_STEAMID_LENGTH);

	if (votes == Kick)
	{
		CPrintToChatAll("CallVote {green}%s{default}: {blue}%N{default} ({blue}%s{default}) ({blue}%N{default}) called the vote.", sTypeVotes[votes], iClient, sSteamID, iTarget);
	}
	else
		CPrintToChatAll("CallVote {green}%s{default}: {blue}%N{default} ({blue}%s{default}) called the vote.", sTypeVotes[votes], iClient, sSteamID);
}