#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <callvotemanager>
#include <colors>

/*****************************************************************
			G L O B A L   V A R S
*****************************************************************/

#define PLUGIN_VERSION	  "1.0"
#define CONSOLE			  0
#define MAX_AUTHID_LENGTH 64 /**< Maximum buffer required to store any AuthID type */
#define DIR_CALLVOTE	  "logs/callvote.log"

/**
 * Player profile.
 *
 */
enum struct PlayerInfo
{
	int	 Client;						// client index
	char Steamid[MAX_AUTHID_LENGTH];	// Player SteamID
	int	 Kick;							// kick voting call amount
	int	 Target;						// Target kicked
}

PlayerInfo g_Players[MAXPLAYERS + 1];

/**
 * Caller profile.
 *
 */
enum struct ClientCaller
{
	int	 Client;
	bool IsKick;
}

ClientCaller g_Caller = { 0, false };

char		 sLogPath[PLATFORM_MAX_PATH];

ConVar
	g_cvarEnable,
	g_cvarKickLimit,
	g_cvarVoteDuration,

	sv_vote_timer_duration;

EngineVersion g_iEngine;

/*****************************************************************
			L I B R A R Y   I N C L U D E S
*****************************************************************/

#include "callvote/kicklimit_sql.sp"

/**
 * Called before OnPluginStart, in case the plugin wants to check for load failure.
 * This is called even if the plugin type is "private."  Any natives from modules are
 * not available at this point.  Thus, this forward should only be used for explicit
 * pre-emptive things, such as adding dynamic natives, setting certain types of load
 * filters (such as not loading the plugin for certain games).
 *
 * @note It is not safe to call externally resolved natives until OnPluginStart().
 * @note Any sort of RTE in this function will cause the plugin to fail loading.
 * @note If you do not return anything, it is treated like returning success.
 * @note If a plugin has an AskPluginLoad2(), AskPluginLoad() will not be called.
 *
 * @param myself        Handle to the plugin.
 * @param late          Whether or not the plugin was loaded "late" (after map load).
 * @param error         Error message buffer in case load failed.
 * @param err_max       Maximum number of characters for error message buffer.
 * @return              APLRes_Success for load success, APLRes_Failure or APLRes_SilentFailure otherwise
 */
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	if (!L4D_IsEngineLeft4Dead2())
	{
		strcopy(error, err_max, "Plugin only support L4D2 engine");
		return APLRes_Failure;
	}
	return APLRes_Success;
}

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
	name		= "Call Vote Kick Limit",
	author		= "lechuga",
	description = "Limits the amount of callvote kick",
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
	LoadTranslation("callvote_kicklimit.phrases");
	CreateConVar("sm_cvkl_version", PLUGIN_VERSION, "Plugin version", FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_SPONLY | FCVAR_DONTRECORD);

	g_cvarEnable	   = CreateConVar("sm_cvkl_enable", "1", "Enable plugin", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvarKickLimit	   = CreateConVar("sm_cvkl_kicklimit", "1", "Kick limit", FCVAR_NOTIFY, true, 0.0);
	g_cvarVoteDuration = CreateConVar("sm_cvkl_voteduration", "-1", "How long to allow voting on an issue. -1 Default", FCVAR_NOTIFY, true, -1.0);

	g_cvarVoteDuration.AddChangeHook(ConVarChanged_VoteDuration);
	sv_vote_timer_duration = FindConVar("sv_vote_timer_duration");
	sv_vote_timer_duration.AddChangeHook(ConVarChanged_VoteDuration);

	HookUserMessage(GetUserMessageId("VotePass"), Message_VotePass);
	HookUserMessage(GetUserMessageId("VoteFail"), Message_VoteFail);

	// Build log path
	BuildPath(Path_SM, sLogPath, sizeof(sLogPath), DIR_CALLVOTE);

	OPS_SQL();

	AutoExecConfig(true, "callvote_kicklimit");
	ApplyConVars();

	for (int i = 1; i <= MaxClients; i++)
		if (IsClientConnected(i))
		{
			char sSteamId[MAX_AUTHID_LENGTH];
			GetClientAuthId(i, AuthId_Engine, sSteamId, MAX_AUTHID_LENGTH);
			OnClientAuthorized(i, sSteamId);
		}
}

/**
 * Replicates the value change of the ConVar Difficulty
 * @param hConVar ConVar handle
 * @param sOldValue Old value
 * @param sNewValue New value
 * @noreturn
 */
public void ConVarChanged_VoteDuration(Handle hConVar, const char[] sOldValue, const char[] sNewValue)
{
	if (g_cvarVoteDuration.IntValue > -1 && (g_cvarVoteDuration.IntValue != sv_vote_timer_duration.IntValue))
		sv_vote_timer_duration.SetInt(g_cvarVoteDuration.IntValue);
	else if (g_cvarVoteDuration.IntValue == -1)
		sv_vote_timer_duration.RestoreDefault();
}

/**
 * Applies ConVars after they are loaded from autoexec
 * @noreturn
 */
public void ApplyConVars()
{
	if (g_cvarVoteDuration.IntValue > -1 && (g_cvarVoteDuration.IntValue != sv_vote_timer_duration.IntValue))
		sv_vote_timer_duration.SetInt(g_cvarVoteDuration.IntValue);
	else if (g_cvarVoteDuration.IntValue == -1)
		sv_vote_timer_duration.RestoreDefault();
}

/**
 * Called when a client receives an auth ID.  The state of a client's
 * authorization as an admin is not guaranteed here.  Use
 * OnClientPostAdminCheck() if you need a client's admin status.
 *
 * This is called by bots, but the ID will be "BOT".
 *
 * @param client        Client index.
 * @param auth          Client Steam2 id, if available, else engine auth id.
 */
public void OnClientAuthorized(int iClient, const char[] sAuth)
{
	if (!g_cvarEnable.BoolValue || IsFakeClient(iClient))
		return;

	g_Players[iClient].Client = iClient;
	Format(g_Players[iClient].Steamid, MAX_AUTHID_LENGTH, sAuth);
	g_Players[iClient].Kick	  = 0;
	g_Players[iClient].Target = 0;

	GetCountKick(hGetKick, iClient, sAuth);
}

/**
 * Starts when a voting call begins, indicates the user who started it and the type of voting.
 *
 * @param client The client who started the vote.
 * @param votes The type of voting.
 * @param Target The target of the vote. if the vote is not kick, this value will always be 0
 */
public void CallVote_Start(int iClient, TypeVotes iVotes, int iTarget)
{
	if (iVotes != Kick)
	{
		g_Caller.IsKick = false;
		return;
	}

	if (g_cvarKickLimit.IntValue <= g_Players[iClient].Kick)
	{
		char sBuffer[128];
		Format(sBuffer, sizeof(sBuffer), "%t", "KickReached", g_Players[iClient].Kick, g_cvarKickLimit.IntValue);
		CallVote_Reject(iClient, sBuffer);
		return;
	}

	g_Caller.Client			  = iClient;
	g_Caller.IsKick			  = true;
	g_Players[iClient].Target = iTarget;
	return;
}

/*
 *	VotePass
 *	Note: Sent to all players after a vote passes.
 *
 *	Structure:
 *			byte	team	Team index or 255 for all
 *			string	details	Vote success translation string
 *			string	param1	Vote winner
 */
public Action Message_VotePass(UserMsg msg_id, BfRead bf, const int[] players, int playersNum, bool reliable, bool init)
{
	if (!g_Caller.IsKick)
		return Plugin_Continue;

	g_Players[g_Caller.Client].Kick++;
	sqlinsert(g_Caller.Client, g_Players[g_Caller.Client].Target);

	if (g_Players[g_Caller.Client].Target != g_Caller.Client)
		CPrintToChat(g_Caller.Client, "%s %t", "Tag", "KickLimit", g_Players[g_Caller.Client].Kick, g_cvarKickLimit.IntValue);

	g_Players[g_Caller.Client].Target = 0;
	g_Caller.Client					  = 0;
	g_Caller.IsKick					  = false;
	return Plugin_Continue;
}

/*
 *	VoteFail
 *	Note: Sent to all players after a vote fails.
 *
 *	Structure:
 *			byte	team	Team index or 255 for all
 */
public Action Message_VoteFail(UserMsg msg_id, BfRead bf, const int[] players, int playersNum, bool reliable, bool init)
{
	if (!g_Caller.IsKick)
		return Plugin_Continue;

	g_Caller.Client = 0;
	return Plugin_Continue;
}

/**
 * Returns a valid client indexed.
 *
 * @param client		Player's index.
 * @return				true if the client is valid, false if not.
 */
stock bool IsValidClient(int iClient)
{
	return (IsValidClientIndex(iClient) && IsClientInGame(iClient) && !IsFakeClient(iClient));
}

/**
 * Client indexed.
 *
 * @param client		Player's index.
 * @return				true if the client is valid, false if not.
 */
stock bool IsValidClientIndex(int iClient)
{
	return (iClient > 0 && iClient <= MaxClients);
}

/**
 * @brief Returns if the server is running on Left 4 Dead 2
 *
 * @return					Returns true if server is running on Left 4 Dead 2
 */
stock bool L4D_IsEngineLeft4Dead2()
{
	if (g_iEngine == Engine_Unknown)
	{
		g_iEngine = GetEngineVersion();
	}

	return g_iEngine == Engine_Left4Dead2;
}

/**
 * Check if the translation file exists
 *
 * @param translation	Translation name.
 * @noreturn
 */
void LoadTranslation(const char[] translation)
{
	char
		sPath[PLATFORM_MAX_PATH],
		sName[64];

	Format(sName, sizeof(sName), "translations/%s.txt", translation);
	BuildPath(Path_SM, sPath, sizeof(sPath), sName);
	if (!FileExists(sPath))
		SetFailState("Missing translation file %s.txt", translation);

	LoadTranslations(translation);
}

/*
 * @brief: Print debug message to log file
 * @param: sMessage - Message to print
 * @param: any - Arguments
 */
void log(const char[] sMessage, any...)
{
	static char sFormat[512];

	// Format message
	VFormat(sFormat, sizeof(sFormat), sMessage, 2);

	// Print to log file
	File file = OpenFile(sLogPath, "a+");
	LogToFileEx(sLogPath, "%s", sFormat);
	delete file;
}

// =======================================================================================
// Bibliography
// https://developer.valvesoftware.com/wiki/List_of_L4D2_Cvars
// https://wiki.alliedmods.net/Left_4_Voting_2
// https://forums.alliedmods.net/showthread.php?p=1582772
// https://github.com/SirPlease/L4D2-Competitive-Rework
// =======================================================================================