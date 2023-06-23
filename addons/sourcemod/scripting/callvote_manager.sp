#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#undef REQUIRE_EXTENSIONS
#include <builtinvotes>
#define REQUIRE_EXTENSIONS
#include <colors>

/*****************************************************************
			G L O B A L   V A R S
*****************************************************************/

#define PLUGIN_VERSION		  "1.0"
#define DIR_CALLVOTE		  "logs/callvote.log"
#define CONSOLE				  0
#define MAX_REASON_LENGTH	  512

/**
 * @section Bitwise values definitions for type vote.
 */
#define VOTE_CHANGEDIFFICULTY (1 << 0)	  // 1
#define VOTE_RESTARTGAME	  (1 << 1)	  // 2
#define VOTE_KICK			  (1 << 2)	  // 4
#define VOTE_CHANGEMISSION	  (1 << 3)	  // 8
#define VOTE_RETURNTOLOBBY	  (1 << 4)	  // 16
#define VOTE_CHANGECHAPTER	  (1 << 5)	  // 32
#define VOTE_CHANGEALLTALK	  (1 << 6)	  // 64

enum TypeVotes
{
	ChangeDifficulty = 0,
	RestartGame		 = 1,
	Kick			 = 2,
	ChangeMission	 = 3,
	ReturnToLobby	 = 4,
	ChangeChapter	 = 5,
	ChangeAllTalk	 = 6,

	TypeVotes_Size	 = 7
};

char sTypeVotes[TypeVotes_Size][] = {
	"ChangeDifficulty",
	"RestartGame",
	"Kick",
	"ChangeMission",
	"ReturnToLobby",
	"ChangeChapter",
	"ChangeAllTalk"
};

enum CampaignCode
{
	l4d2c1			  = 0,
	l4d2c2			  = 1,
	l4d2c3			  = 2,
	l4d2c4			  = 3,
	l4d2c5			  = 4,
	l4d2c6			  = 5,
	l4d2c7			  = 6,
	l4d2c8			  = 7,
	l4d2c9			  = 8,
	l4d2c10			  = 9,
	l4d2c11			  = 10,
	l4d2c12			  = 11,
	l4d2c13			  = 12,

	CampaignCode_size = 13,
};

char sCampaignCode[CampaignCode_size][] = {
	"l4d2c1",
	"l4d2c2",
	"l4d2c3",
	"l4d2c4",
	"l4d2c5",
	"l4d2c6",
	"l4d2c7",
	"l4d2c8",
	"l4d2c9",
	"l4d2c10",
	"l4d2c11",
	"l4d2c12",
	"l4d2c13"
};

enum L4D2_Team
{
	L4D2Team_None	   = 0,
	L4D2Team_Spectator = 1,
	L4D2Team_Survivor  = 2,
	L4D2Team_Infected  = 3,

	L4D2Team_Size	   = 4
};

ConVar
	// g_cvarDebug,
	g_cvarlog,
	g_cvarBuiltinVote,
	g_cvarSpecVote,
	g_cvarAnnouncer,
	g_cvarCreationTimer,

	g_cvarDifficulty,
	g_cvarRestart,
	g_cvarMission,
	g_cvarLobby,
	g_cvarChapter,
	g_cvarAllTalk,

	g_cvarKick,
	g_cvarBanDuration,
	g_cvarAdminInmunity,
	g_cvarVipInmunity,
	g_cvarSTVInmunity,
	g_cvarSelfInmunity,
	g_cvarBotInmunity;

bool		  g_bBuiltinVotes = false;
EngineVersion g_iEngine;
char
	sLogPath[PLATFORM_MAX_PATH],
	g_sReason[MAX_REASON_LENGTH + 1];
float g_fLastVote;
int
	g_iFlagsAdmin,
	g_iFlagsVip,
	g_iVoteRejectClient = -1;

GlobalForward g_ForwardCallVote;

/*****************************************************************
			L I B R A R Y   I N C L U D E S
*****************************************************************/

#include "callvote/manager_sql.sp"
#include "callvote/manager_convar.sp"

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

	// <builtinvotes>
	MarkNativeAsOptional("IsBuiltinVoteInProgress");
	MarkNativeAsOptional("CheckBuiltinVoteDelay");

	RegPluginLibrary("callvotemanager");
	g_ForwardCallVote = CreateGlobalForward("CallVote_Start", ET_Ignore, Param_Cell, Param_Cell, Param_Cell);
	CreateNative("CallVote_Reject", Native_CallVote_Reject);

	return APLRes_Success;
}

/**
 * Called after all plugins have been loaded.  This is called once for
 * every plugin.  If a plugin late loads, it will be called immediately
 * after OnPluginStart().
 */
public void OnAllPluginsLoaded()
{
	g_bBuiltinVotes = LibraryExists("BuiltinVotes");
}

/**
 * Returns whether a library exists.  This function should be considered
 * expensive; it should only be called on plugin to determine availability
 * of resources.  Use OnLibraryAdded()/OnLibraryRemoved() to detect changes
 * in libraries.
 *
 * @param name          Library name of a plugin or extension.
 * @return              True if exists, false otherwise.
 */
public void OnLibraryRemoved(const char[] sName)
{
	if (StrEqual(sName, "BuiltinVotes"))
	{
		g_bBuiltinVotes = false;
	}
}

/**
 * Returns whether a library exists.  This function should be considered
 * expensive; it should only be called on plugin to determine availability
 * of resources.  Use OnLibraryAdded()/OnLibraryRemoved() to detect changes
 * in libraries.
 *
 * @param name          Library name of a plugin or extension.
 * @return              True if exists, false otherwise.
 */
public void OnLibraryAdded(const char[] sName)
{
	if (StrEqual(sName, "BuiltinVotes"))
	{
		g_bBuiltinVotes = true;
	}
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
	name		= "Call Vote Manager",
	author		= "lechuga",
	description = "Manage call vote system",
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
	LoadTranslation("callvote_manager.phrases");
	CreateConVar("sm_cvm_version", PLUGIN_VERSION, "Plugin version", FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_SPONLY | FCVAR_DONTRECORD);

	// g_cvarDebug			= CreateConVar("sm_cvm_debug", "0", "Debug messagess/logs", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvarlog			= CreateConVar("sm_cvm_log", "0", "Enable logging flag", FCVAR_NOTIFY, true, 0.0, true, 127.0);
	g_cvarBuiltinVote	= CreateConVar("sm_cvm_builtinvote", "1", "<builtinvotes> support", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvarSpecVote		= CreateConVar("sm_cvm_specvote", "0", "Allow spectators to call vote", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvarAnnouncer		= CreateConVar("sm_cvm_announcer", "1", "Announce voting calls", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvarCreationTimer = CreateConVar("sm_cvm_creationtimer", "-1", "How often someone can individually call a vote. -1 Default", FCVAR_NOTIFY, true, -1.0);

	g_cvarDifficulty	= CreateConVar("sm_cvm_difficulty", "1", "Enable vote ChangeDifficulty", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvarRestart		= CreateConVar("sm_cvm_restart", "1", "Enable vote RestartGame", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvarMission		= CreateConVar("sm_cvm_mission", "1", "Enable vote ChangeMission", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvarLobby			= CreateConVar("sm_cvm_lobby", "1", "Enable vote ReturnToLobby", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvarChapter		= CreateConVar("sm_cvm_chapter", "1", "Enable vote ChangeChapter", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvarAllTalk		= CreateConVar("sm_cvm_alltalk", "1", "Enable vote ChangeAllTalk", FCVAR_NOTIFY, true, 0.0, true, 1.0);

	// ConVar that refer to the kick vote call
	g_cvarKick			= CreateConVar("sm_cvm_kick", "1", "Enable vote Kick", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvarBanDuration	= CreateConVar("sm_cvm_banduration", "-1", "How long should a kick vote ban someone from the server? (in minutes). -1 Default", FCVAR_NOTIFY, true, -1.0);
	g_cvarAdminInmunity = CreateConVar("sm_cvm_admininmunity", "", "Admins are immune to kick votes. Specify admin flags or blank. Not immune to kick flag", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvarVipInmunity	= CreateConVar("sm_cvm_vipinmunity", "", "Vips are immune to kick votes, Specify admin flags or blank. Not immune to kick flag", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvarSTVInmunity	= CreateConVar("sm_cvm_stvinmunity", "1", "SourceTV is immune to votekick", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvarSelfInmunity	= CreateConVar("sm_cvm_selfinmunity", "1", "Immunity to self-kick", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	g_cvarBotInmunity	= CreateConVar("sm_cvm_botinmunity", "1", "Immunity to bots", FCVAR_NOTIFY, true, 0.0, true, 1.0);

	OPS_ConVar();
	OPS_SQL();

	// Listen when a user issues a voting call
	AddCommandListener(Listener_CallVote, "callvote");

	// Build log path
	BuildPath(Path_SM, sLogPath, sizeof(sLogPath), DIR_CALLVOTE);

	AutoExecConfig(true, "callvote_manager");
	ApplyConVars();
}

/**
 * Rejects a vote in process, before being issued.
 *
 * @param client The client who started the vote.
 * @param reason The reason for the rejection.
 * @error Invalid client index
 * @error Invalid length reason
 * @error Invalid numParams
 */
int Native_CallVote_Reject(Handle plugin, int numParams)
{
	if (numParams <= 1 && 3 <= numParams)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid numParams (%d/2)", numParams);

	int client = GetNativeCell(1);
	if (client < 1 || client > MaxClients)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d!", client);
	g_iVoteRejectClient = client;

	int iLen;
	GetNativeStringLength(2, iLen);
	if (iLen > MAX_REASON_LENGTH)
		return ThrowNativeError(SP_ERROR_NATIVE, "Invalid length reason (%d/%d)", iLen, MAX_REASON_LENGTH);

	GetNativeString(2, g_sReason, iLen + 1);
	return 1;
}

public void OnMapStart()
{
	g_fLastVote = 0.0;
}

/**
 * Intercept the voting call
 * @param client Client index
 * @param command Command name
 * @param args Arguments
 * @return Plugin_Continue if the vote is allowed, Plugin_Handled otherwise
 */
public Action Listener_CallVote(int client, const char[] command, int args)
{
	// Check if the client is console
	if (client == CONSOLE)
	{
		CReplyToCommand(client, "%t Votes can only be issued from a valid client.", "Tag");
		return Plugin_Handled;
	}

	// Check if the client is spectating
	if (g_cvarSpecVote.BoolValue && view_as<L4D2_Team>(GetClientTeam(client)) == L4D2Team_Spectator)
	{
		CPrintToChat(client, "%t %t", "Tag", "SpecVote");
		return Plugin_Handled;
	}

	// Check if we can even do a vote
	if (g_bBuiltinVotes && g_cvarBuiltinVote.BoolValue && !IsNewBuiltinVoteAllowed)
	{
		CPrintToChat(client, "%t %t", "Tag", "TryAgain", CheckBuiltinVoteDelay());
		return Plugin_Handled;
	}

	float fDifLastVote = GetEngineTime() - g_fLastVote;
	// Minimum time that is required by the voting system itself before another vote can be called
	if (fDifLastVote <= 5.5)
	{
		CPrintToChat(client, "%t %t", "Tag", "TryAgain", RoundFloat(5.5 - fDifLastVote));
		return Plugin_Handled;
	}
	else if (fDifLastVote <= sv_vote_creation_timer.FloatValue)
	{
		CPrintToChat(client, "%t %t", "Tag", "TryAgain", RoundFloat(sv_vote_creation_timer.FloatValue - fDifLastVote));
		return Plugin_Handled;
	}

	// Storage
	char sVoteType[32];
	char sVoteArgument[32];

	// Get Vote Type
	GetCmdArg(1, sVoteType, sizeof(sVoteType));
	GetCmdArg(2, sVoteArgument, sizeof(sVoteArgument));

	// ------------------------------------------------------------
	// Change Difficulty <Impossible|Expert|Hard|Normal>
	// ------------------------------------------------------------
	if (strcmp(sVoteType, sTypeVotes[ChangeDifficulty], false) == 0)
	{
		if (!g_cvarDifficulty.BoolValue)
		{
			CPrintToChat(client, "%t %t", "Tag", "VoteDisabled");
			return Plugin_Continue;	   // it is disabled by sv_vote_issue_change_difficulty_allowed
		}

		if (args != 2)
			return Plugin_Continue;

		char sCVarDifficulty[32];
		z_difficulty.GetString(sCVarDifficulty, sizeof(sCVarDifficulty));

		if (strcmp(sVoteArgument, sCVarDifficulty, false) == 0)
		{
			CPrintToChat(client, "%t %t", "Tag", "SameDifficulty");
			return Plugin_Handled;
		}

		ForwardCallVote(client, ChangeDifficulty);

		// Check if the vote was rejected
		if (g_iVoteRejectClient != -1 && g_iVoteRejectClient == client)
		{
			CPrintToChat(client, "%t VoteReject: %s", "Tag", g_sReason);
			CleanVoteReject();
			return Plugin_Handled;
		}

		// We translate the difficulty
		char sDifficulty[32];
		Format(sDifficulty, sizeof(sDifficulty), "%t", sVoteArgument);

		if (g_cvarlog.IntValue & VOTE_CHANGEDIFFICULTY)
			log("Caller %N | Vote %s - %s", client, sTypeVotes[ChangeDifficulty], sDifficulty);

		if (g_cvarSQL.IntValue & VOTE_CHANGEDIFFICULTY)
			sqllog(ChangeDifficulty, client);

		announcer("%t", "ChangeDifficulty", client, sDifficulty);
	}
	// ------------------------------------------------------------
	// Restart Game
	// ------------------------------------------------------------
	else if (strcmp(sVoteType, sTypeVotes[RestartGame], false) == 0)
	{
		if (!g_cvarRestart.BoolValue)
		{
			CPrintToChat(client, "%t %t", "Tag", "VoteDisabled");
			return Plugin_Continue;	   // it is disabled by sv_vote_issue_restart_game_allowed
		}

		if (args != 1)
			return Plugin_Continue;

		ForwardCallVote(client, RestartGame);

		// Check if the vote was rejected
		if (g_iVoteRejectClient != -1 && g_iVoteRejectClient == client)
		{
			CPrintToChat(client, "%t VoteReject: %s", "Tag", g_sReason);
			CleanVoteReject();
			return Plugin_Handled;
		}

		if (g_cvarlog.IntValue & VOTE_RESTARTGAME)
			log("Caller %N | Vote %s", client, sTypeVotes[RestartGame]);

		if (g_cvarSQL.IntValue & VOTE_RESTARTGAME)
			sqllog(RestartGame, client);

		announcer("%t", "RestartGame", client);
	}
	// ------------------------------------------------------------
	// Kick <userID>
	// ------------------------------------------------------------
	else if (strcmp(sVoteType, sTypeVotes[Kick], false) == 0)
	{
		if (!g_cvarKick.BoolValue)
		{
			CPrintToChat(client, "%t %t", "Tag", "VoteDisabled");
			return Plugin_Continue;	   // it is disabled by sv_vote_issue_kick_allowed
		}

		int iTarget = GetClientOfUserId(StringToInt(sVoteArgument));

		CPrintToChatAll("%t Client %N | sArg %s | iArgs %d | Target %d | cmd %s", "Tag", client, sVoteArgument, StringToInt(sVoteArgument), iTarget, command);
		CPrintToChatAll("%t args %d | %s", "Tag", sizeof(args), args);

		if (args != 2 || iTarget == CONSOLE)
			return Plugin_Continue;

		if (g_cvarSTVInmunity.BoolValue && IsClientConnected(client) && IsClientSourceTV(iTarget))
		{
			CPrintToChat(client, "%t %t", "Tag", "SourceTVKick");
			return Plugin_Handled;
		}

		if (g_cvarBotInmunity.BoolValue && IsClientConnected(client) && !IsClientSourceTV(iTarget) && IsFakeClient(iTarget))
		{
			CPrintToChat(client, "%t %t", "Tag", "BotKick");
			return Plugin_Handled;
		}

		if (g_cvarSelfInmunity.BoolValue && iTarget == client)
		{
			CPrintToChat(client, "%t %t", "Tag", "KickSelf");
			return Plugin_Handled;
		}

		if (!IsFlagC(client) && (IsAdmin(iTarget) || IsVip(iTarget)))
		{
			CPrintToChat(client, "%t %t", "Tag", "Inmunity");
			return Plugin_Handled;
		}

		/* Start function call */
		Call_StartForward(g_ForwardCallVote);

		/* Push parameters one at a time */
		Call_PushCell(client);
		Call_PushCell(Kick);
		Call_PushCell(iTarget);

		/* Finish the call */
		Call_Finish();

		// Check if the vote was rejected
		if (g_iVoteRejectClient != -1 && g_iVoteRejectClient == client)
		{
			CPrintToChat(client, "%t VoteReject: %s", "Tag", g_sReason);
			CleanVoteReject();
			return Plugin_Handled;
		}

		if (g_cvarlog.IntValue & VOTE_KICK)
			log("Caller %N | Vote %s - %N", client, sTypeVotes[Kick], iTarget);

		if (g_cvarSQL.IntValue & VOTE_KICK)
			sqllog(Kick, client, iTarget);

		announcer("%t", "Kick", client, iTarget);
	}
	// ------------------------------------------------------------
	// Change Map <MapName>
	// ------------------------------------------------------------
	else if (strcmp(sVoteType, sTypeVotes[ChangeMission], false) == 0)
	{
		if (!g_cvarMission.BoolValue)
		{
			CPrintToChat(client, "%t %t", "Tag", "VoteDisabled");
			return Plugin_Continue;	   // it is disabled by sv_vote_issue_change_mission_allowed
		}

		if (args != 2)
			return Plugin_Continue;

		ForwardCallVote(client, ChangeMission);

		// Check if the vote was rejected
		if (g_iVoteRejectClient != -1 && g_iVoteRejectClient == client)
		{
			CPrintToChat(client, "%t %s", "Tag", g_sReason);
			CleanVoteReject();
			return Plugin_Handled;
		}

		// We verify if the map is official for translation
		int	 iCode = Campaign_Code(sVoteArgument);
		char sCampaign[32];
		if (iCode == -1)
			Format(sCampaign, sizeof(sCampaign), "%s", sVoteArgument);
		else
			Format(sCampaign, sizeof(sCampaign), "%t", sCampaignCode[iCode]);

		if (g_cvarlog.IntValue & VOTE_CHANGEMISSION)
			log("Caller %N | Vote %s - %s", client, sTypeVotes[ChangeMission], sVoteArgument);

		if (g_cvarSQL.IntValue & VOTE_CHANGEMISSION)
			sqllog(ChangeMission, client);

		announcer("%t", "ChangeMission", client, sCampaign);
	}
	// ------------------------------------------------------------
	// Return to Lobby
	// ------------------------------------------------------------
	else if (strcmp(sVoteType, sTypeVotes[ReturnToLobby], false) == 0)
	{
		if (!g_cvarLobby.BoolValue)
		{
			CPrintToChat(client, "%t %t", "Tag", "VoteDisabled");
			return Plugin_Handled;
		}

		if (args != 1)
			return Plugin_Continue;

		ForwardCallVote(client, ReturnToLobby);

		// Check if the vote was rejected
		if (g_iVoteRejectClient != -1 && g_iVoteRejectClient == client)
		{
			CPrintToChat(client, "%t VoteReject: %s", "Tag", g_sReason);
			CleanVoteReject();
			return Plugin_Handled;
		}

		if (g_cvarlog.IntValue & VOTE_RETURNTOLOBBY)
			log("Caller %N | Vote %s", client, sTypeVotes[ReturnToLobby]);

		if (g_cvarSQL.IntValue & VOTE_RETURNTOLOBBY)
			sqllog(ReturnToLobby, client);
		announcer("%t", "ReturnToLobby", client);
	}
	// ------------------------------------------------------------
	// Change Chapter <MapCode>
	// ------------------------------------------------------------
	else if (strcmp(sVoteType, sTypeVotes[ChangeChapter], false) == 0)
	{
		if (!g_cvarChapter.BoolValue)
		{
			CPrintToChat(client, "%t %t", "Tag", "VoteDisabled");
			return Plugin_Handled;
		}

		if (args != 2)
			return Plugin_Continue;

		ForwardCallVote(client, ChangeChapter);

		// Check if the vote was rejected
		if (g_iVoteRejectClient != -1 && g_iVoteRejectClient == client)
		{
			CPrintToChat(client, "%t VoteReject: %s", "Tag", g_sReason);
			CleanVoteReject();
			return Plugin_Handled;
		}

		if (g_cvarlog.IntValue & VOTE_CHANGECHAPTER)
			log("Caller %N | Vote %s - %s", client, sTypeVotes[ChangeChapter], sVoteArgument);

		if (g_cvarSQL.IntValue & VOTE_CHANGECHAPTER)
			sqllog(ChangeChapter, client);

		announcer("%t", "ChangeChapter", client, sVoteArgument);
	}
	// ------------------------------------------------------------
	// Change All Talk
	// ------------------------------------------------------------
	else if (strcmp(sVoteType, sTypeVotes[ChangeAllTalk], false) == 0)
	{
		if (!g_cvarAllTalk.BoolValue)
			return Plugin_Handled;

		if (args != 1)
			return Plugin_Continue;

		ForwardCallVote(client, ChangeAllTalk);

		// Check if the vote was rejected
		if (g_iVoteRejectClient != -1 && g_iVoteRejectClient == client)
		{
			CPrintToChat(client, "%t VoteReject: %s", "Tag", g_sReason);
			CleanVoteReject();
			return Plugin_Handled;
		}

		if (g_cvarlog.IntValue & VOTE_CHANGEALLTALK)
			log("Caller %N | Vote %s", client, sTypeVotes[ChangeAllTalk]);

		if (g_cvarSQL.IntValue & VOTE_CHANGEALLTALK)
			sqllog(ChangeAllTalk, client);
		announcer("%t", "ChangeAllTalk", client);
	}

	g_fLastVote = GetEngineTime();
	return Plugin_Continue;
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

/*
 * @brief: Print announcer message to log file
 * @param: sMessage - Message to print
 * @param: any - Arguments
 */
void announcer(const char[] sMessage, any...)
{
	if (!g_cvarAnnouncer.BoolValue)
		return;

	static char sFormat[512];

	// Format message
	VFormat(sFormat, sizeof(sFormat), sMessage, 2);

	CPrintToChatAll("%t %s", "Tag", sFormat);
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

/**
 * @brief Return if a user has admin or root flag
 * @param client			Client index
 * @return					True if it has an admin flag or is root, False if it has no flags.
 */
bool IsAdmin(const int client)
{
	if (g_iFlagsAdmin == 0)
		return false;

	int iClientFlags = GetUserFlagBits(client);
	return view_as<bool>((iClientFlags & g_iFlagsAdmin) || (iClientFlags & ADMFLAG_ROOT));
}

/**
 * @brief Return if a user has vip flag
 * @param client			Client index
 * @return					True if it has an vip flag, False if it has no flags.
 */
bool IsVip(const int client)
{
	if (g_iFlagsVip == 0)
		return false;

	int iClientFlags = GetUserFlagBits(client);
	return view_as<bool>(iClientFlags & g_iFlagsVip);
}

/**
 * @brief Return if a user has kick flag or root
 * @param client			Client index
 * @return					True if it has an kick flag or root, False if it has no flags.
 */
bool IsFlagC(const int client)
{
	int iClientFlags = GetUserFlagBits(client);
	return view_as<bool>(iClientFlags & FlagToBit(Admin_Kick) || (iClientFlags & ADMFLAG_ROOT));
}

/**
 * @brief Clean the variables used by rejecting a vote
 * @noreturn
 */
void CleanVoteReject()
{
	g_sReason[0]		= '\0';
	g_iVoteRejectClient = -1;
}

void ForwardCallVote(int iClient, TypeVotes vote)
{
	/* Start function call */
	Call_StartForward(g_ForwardCallVote);

	/* Push parameters one at a time */
	Call_PushCell(iClient);
	Call_PushCell(vote);
	Call_PushCell(0);

	/* Finish the call */
	Call_Finish();
}

int Campaign_Code(const char[] sCode)
{
	for (int i = 0; i < view_as<int>(CampaignCode_size); i++)
	{
		if (strcmp(sCampaignCode[i], sCode, false) == 0)
			return i;
	}
	return -1;
}

// =======================================================================================
// Bibliography
// https://developer.valvesoftware.com/wiki/List_of_L4D2_Cvars
// https://wiki.alliedmods.net/Left_4_Voting_2
// https://forums.alliedmods.net/showthread.php?p=1582772
// https://github.com/SirPlease/L4D2-Competitive-Rework
// =======================================================================================