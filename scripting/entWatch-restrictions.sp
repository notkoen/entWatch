//====================================================================================================
//
// Name: [entWatch] Restrictions
// Author: zaCade, Prometheum, koen, Rushaway
// Description: Handle the restrictions of [entWatch]
//
//====================================================================================================
// Requires Sourcemod Version: 1.10.0.6531 or above
//====================================================================================================
#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <entWatch_core>

/* TODO:
- Load balancer support based on players online (check on connect or after a timer of x seconds)
 */

#define EW_DB_NAME             "EntWatch4"
#define EW_DB_CHARSET          "utf8mb4"
#define EW_DB_COLLATION        "utf8mb4_unicode_ci"
#define EW_SESSION_BAN_TIMEOUT 90
#define EW_CONSOLE_NAME        "Console"
#define EW_SERVER_STEAMID      "SERVER"

ClientSettings_Restrict g_RestrictClients[MAXPLAYERS+1];
enum struct ClientSettings_Restrict
{
	bool bVerified;
	bool bRestricted;
	char szAdminName[32];
	char szAdminSteamID[64];
	char szReason[64];
	int  iDuration;
	int  iTimeStamp;
	int  intTotalEbans;

	void Reset()
	{
		this.bVerified         = false;
		this.bRestricted       = false;
		this.szAdminName[0]    = '\0';
		this.szAdminSteamID[0] = '\0';
		this.szReason[0]       = '\0';
		this.iDuration         = 0;
		this.iTimeStamp        = 0;
		this.intTotalEbans     = 0;
	}
}

enum struct OfflinePlayerData
{
	char szPlayerName[32];
	char szPlayerSteamID[64];
	char szLastItem[32];
	int  iUserID;
	int  iTimeStamp;
	int  iTimeStampStart;
}

ArrayList g_OfflineArray;
OfflinePlayerData g_aMenuBuffer[MAXPLAYERS+1];

/* CVARS */
ConVar g_hCVar_UseReasonMenu;
ConVar g_hCVar_DefaultBanReason;
ConVar g_hCVar_DefaultUnbanReason;
ConVar g_hCVar_DefaultBanTime;
ConVar g_hCVar_AdminBanLong;
ConVar g_hCVar_EbanInvalidSteamID;
ConVar g_hCVar_MaxBanTime;
ConVar g_hCVar_DetailedStatus;
ConVar g_hCVar_DropOnEBan;
ConVar g_hCVar_OfflineClearRecords;
ConVar g_hCVar_Admin_OfflineLong;

bool g_bLate = false;
bool g_bUseReasonMenu;
bool g_bCleanedUpTempBans;
bool g_bEbanInvalidSteamID;
bool g_bDetailedStatus;
bool g_bDropItemOnEBan;
char g_sDefaultBanReason[64];
char g_sDefaultUnbanReason[64];
int g_iDefaultBanTime = 0;
int g_iAdminBanLong = 720;
int g_iMaxBanTime = 0;
int g_iOfflineTimeClear = 30;
int g_iOfflineTimeLong = 720;
int g_iCleanupRetryAttempts = 0;

/* DATABASE */
enum EbanDBState
{
	EbanDB_Disconnected = 0,
	EbanDB_Connecting,
	EbanDB_Connected,
	EbanDB_Wait
};
EbanDBState g_eRestrictDBState = EbanDB_Disconnected;

Database g_hRestrictDB = null;
bool g_bIsSQLite = false;
int g_iRestrictConnectLock = 0;
int g_iRestrictSequence = 0;
float g_fRestrictRetryTime = 15.0;

/* FORWARDS */
GlobalForward g_hFwd_OnClientRestricted;
GlobalForward g_hFwd_OnClientUnrestricted;

//----------------------------------------------------------------------------------------------------
// Purpose:
//----------------------------------------------------------------------------------------------------
public Plugin myinfo =
{
	name         = "[entWatch] Restrictions",
	author       = "zaCade, Prometheum, koen, Rushaway",
	description  = "Handle the restrictions of [entWatch]",
	version      = EW_VERSION
};

//----------------------------------------------------------------------------------------------------
// Purpose: Register native functions and plugin library
//----------------------------------------------------------------------------------------------------
public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int errorSize)
{
	CreateNative("EW_ClientRestrict",     Native_ClientRestrict);
	CreateNative("EW_ClientUnrestrict",   Native_ClientUnrestrict);
	CreateNative("EW_IsRestrictedClient", Native_IsRestrictedClient);
	CreateNative("EW_GetClientBanCount",  Native_GetClientBanCount);
	CreateNative("EW_GetClientBanInfo",   Native_GetClientBanInfo);

	RegPluginLibrary("entWatch-restrictions");
	g_bLate = bLate;
	return APLRes_Success;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Initialize plugin, load translations, setup database and commands
//----------------------------------------------------------------------------------------------------
public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("entWatch.phrases");

	if (SQL_CheckConfig(EW_DB_NAME))
		Database_Connect();
	else
		SetFailState("Could not find \"%s\" entry in databases.cfg.", EW_DB_NAME);

	g_hFwd_OnClientRestricted   = new GlobalForward("EW_OnClientRestricted",   ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_String);
	g_hFwd_OnClientUnrestricted = new GlobalForward("EW_OnClientUnrestricted", ET_Ignore, Param_Cell, Param_Cell, Param_String);

	g_hCVar_UseReasonMenu       = CreateConVar("sm_eban_use_reason_menu",      "0",                     "Use menu to choose reason when missing", _, true, 0.0, true, 1.0);
	g_hCVar_DefaultBanReason    = CreateConVar("sm_eban_default_reason",       "Item misuse",           "Default eban reason (max 64 chars)");
	g_hCVar_DefaultUnbanReason  = CreateConVar("sm_eban_default_unban_reason", "Giving another chance", "Default e-unban reason (max 64 chars)");
	g_hCVar_DefaultBanTime      = CreateConVar("sm_eban_default_time",         "0",                     "Default eban time in minutes (-1 = session, 0 = permanent)", _, true, -1.0, true, 43200.0);
	g_hCVar_AdminBanLong        = CreateConVar("sm_eban_admin_max_minutes",    "720",                   "Max eban duration for non-root admins", _, true, 1.0);
	g_hCVar_EbanInvalidSteamID  = CreateConVar("sm_eban_invalid_steamid_temp", "1",                     "Temporarily eban clients with invalid SteamID", _, true, 0.0, true, 1.0);
	g_hCVar_MaxBanTime          = CreateConVar("sm_eban_max_minutes_cmd",      "0",                     "Max minutes allowed via console command (0 = disabled)", _, true, 0.0);
	g_hCVar_DetailedStatus      = CreateConVar("sm_eban_status_detailed",      "0",                     "Show detailed status in sm_status", _, true, 0.0, true, 1.0);
	g_hCVar_DropOnEBan          = CreateConVar("sm_eban_drop_items",           "1",                     "Drop entWatch items on eban", _, true, 0.0, true, 1.0);

	// Offline eban ConVars
	g_hCVar_OfflineClearRecords = CreateConVar("sm_eban_offline_cache_minutes",     "30",  "Keep disconnected players tracked for X minutes (1-240)", _, true, 1.0, true, 240.0);
	g_hCVar_Admin_OfflineLong   = CreateConVar("sm_eban_offline_admin_max_minutes", "720", "Max minutes non-root admins can offline eban", _, true, 1.0);

	g_hCVar_UseReasonMenu.AddChangeHook(OnCvarChanged);
	g_hCVar_DefaultBanReason.AddChangeHook(OnCvarChanged);
	g_hCVar_DefaultUnbanReason.AddChangeHook(OnCvarChanged);
	g_hCVar_DefaultBanTime.AddChangeHook(OnCvarChanged);
	g_hCVar_AdminBanLong.AddChangeHook(OnCvarChanged);
	g_hCVar_EbanInvalidSteamID.AddChangeHook(OnCvarChanged);
	g_hCVar_MaxBanTime.AddChangeHook(OnCvarChanged);
	g_hCVar_DetailedStatus.AddChangeHook(OnCvarChanged);
	g_hCVar_DropOnEBan.AddChangeHook(OnCvarChanged);
	g_hCVar_OfflineClearRecords.AddChangeHook(OnCvarChanged);
	g_hCVar_Admin_OfflineLong.AddChangeHook(OnCvarChanged);

	// Cache values
	g_bUseReasonMenu = g_hCVar_UseReasonMenu.BoolValue;
	g_iDefaultBanTime = g_hCVar_DefaultBanTime.IntValue;
	g_iAdminBanLong = g_hCVar_AdminBanLong.IntValue;
	g_bEbanInvalidSteamID = g_hCVar_EbanInvalidSteamID.BoolValue;
	g_iMaxBanTime = g_hCVar_MaxBanTime.IntValue;
	g_bDetailedStatus = g_hCVar_DetailedStatus.BoolValue;
	g_bDropItemOnEBan = g_hCVar_DropOnEBan.BoolValue;
	g_hCVar_DefaultBanReason.GetString(g_sDefaultBanReason, sizeof(g_sDefaultBanReason));
	g_hCVar_DefaultUnbanReason.GetString(g_sDefaultUnbanReason, sizeof(g_sDefaultUnbanReason));
	g_iOfflineTimeClear = g_hCVar_OfflineClearRecords.IntValue;
	g_iOfflineTimeLong = g_hCVar_Admin_OfflineLong.IntValue;

	RegAdminCmd("sm_eban",   Command_ClientRestrict,   ADMFLAG_BAN);
	RegAdminCmd("sm_eunban", Command_ClientUnrestrict, ADMFLAG_UNBAN);
	RegAdminCmd("sm_eoban",  Command_ClientOfflineRestrict, ADMFLAG_BAN);

	RegConsoleCmd("sm_restrictions", Command_DisplayRestrictions);
	RegConsoleCmd("sm_status",       Command_DisplayStatus);

	// Ensure periodic refresh running
	CreateTimer(30.0, Timer_Restrict_Refresh, _, TIMER_REPEAT);

	// Initialize offline eban system
	if (g_OfflineArray == null)
		g_OfflineArray = new ArrayList(sizeof(OfflinePlayerData));

	// Create offline eban cleanup timer
	CreateTimer(60.0, Timer_OfflineEban_Cleanup, _, TIMER_REPEAT);

	// Late load
	if (!g_bLate)
		return;

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientConnected(client))
			continue;

		if (!IsClientInGame(client) || IsFakeClient(client))
			continue;

		OfflinePlayer_TrackOrUpdate(client, "None", true);

		if (g_RestrictClients[client].bVerified)
			continue;

		Database_UpdateClientRestrictionData(client);
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose: Handle cvar changes
//----------------------------------------------------------------------------------------------------
void OnCvarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if (convar == g_hCVar_UseReasonMenu)
		g_bUseReasonMenu = g_hCVar_UseReasonMenu.BoolValue;
	else if (convar == g_hCVar_DefaultBanReason)
		g_hCVar_DefaultBanReason.GetString(g_sDefaultBanReason, sizeof(g_sDefaultBanReason));
	else if (convar == g_hCVar_DefaultUnbanReason)
		g_hCVar_DefaultUnbanReason.GetString(g_sDefaultUnbanReason, sizeof(g_sDefaultUnbanReason));
	else if (convar == g_hCVar_DefaultBanTime)
		g_iDefaultBanTime = g_hCVar_DefaultBanTime.IntValue;
	else if (convar == g_hCVar_AdminBanLong)
		g_iAdminBanLong = g_hCVar_AdminBanLong.IntValue;
	else if (convar == g_hCVar_EbanInvalidSteamID)
		g_bEbanInvalidSteamID = g_hCVar_EbanInvalidSteamID.BoolValue;
	else if (convar == g_hCVar_MaxBanTime)
		g_iMaxBanTime = g_hCVar_MaxBanTime.IntValue;
	else if (convar == g_hCVar_DetailedStatus)
		g_bDetailedStatus = g_hCVar_DetailedStatus.BoolValue;
	else if (convar == g_hCVar_DropOnEBan)
		g_bDropItemOnEBan = g_hCVar_DropOnEBan.BoolValue;
	else if (convar == g_hCVar_OfflineClearRecords)
		g_iOfflineTimeClear = g_hCVar_OfflineClearRecords.IntValue;
	else if (convar == g_hCVar_Admin_OfflineLong)
		g_iOfflineTimeLong = g_hCVar_Admin_OfflineLong.IntValue;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Disconnect from database on plugin end
//----------------------------------------------------------------------------------------------------
public void OnPluginEnd()
{
	Database_Disconnect();
}

//----------------------------------------------------------------------------------------------------
// Purpose: Reset plugin state and clear client data on map change
//----------------------------------------------------------------------------------------------------
public void OnMapStart()
{
	g_bCleanedUpTempBans = false;
	g_iCleanupRetryAttempts = 0;

	Client_ClearAllRestrictionData();
}

//----------------------------------------------------------------------------------------------------
// Purpose: Track player connection for offline eban system
//----------------------------------------------------------------------------------------------------
public void OnClientPostAdminCheck(int client)
{
	OfflinePlayer_TrackOrUpdate(client, "None", true);
}

//----------------------------------------------------------------------------------------------------
// Purpose: Clean up client data and handle offline tracking on disconnect
//----------------------------------------------------------------------------------------------------
public void OnClientDisconnect(int client)
{
	g_RestrictClients[client].Reset();
	OfflinePlayer_OnClientDisconnect(client);
}

//----------------------------------------------------------------------------------------------------
// Purpose: Clean all client data
//----------------------------------------------------------------------------------------------------
void Client_ClearAllRestrictionData()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;

		g_RestrictClients[i].Reset();
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose: Handle sm_eban command - restrict client from using EntWatch items
//----------------------------------------------------------------------------------------------------
public Action Command_ClientRestrict(int client, int args)
{
	if (GetCmdArgs() < 1)
	{
		ReplyToCommand(client, "\x04[entWatch] \x01Usage: sm_eban <#userid/name> [duration] [reason]");
		return Plugin_Handled;
	}

	int len, next_len, iDuration = -1;
	char sArguments[256], sArg[64], sTime[20];

	GetCmdArgString(sArguments, sizeof(sArguments));
	len = BreakString(sArguments, sArg, sizeof(sArg));
	if (len == -1)
	{
		len = 0;
		sArguments[0] = '\0';
	}

	int target = -1;
	if ((target = FindTarget(client, sArg, true)) == -1)
		return Plugin_Handled;

	if (g_RestrictClients[target].bRestricted)
	{
		ReplyToCommand(client, "\x04[entWatch] \x01%N is already restricted", target);
		return Plugin_Handled;
	}

	if ((next_len = BreakString(sArguments[len], sTime, sizeof(sTime))) != -1)
		len += next_len;
	else
	{
		len = 0;
		sArguments[0] = '\0';
	}

	if (!sTime[0] || !StringToIntEx(sTime, iDuration))
		iDuration = g_iDefaultBanTime;

	if (GetCmdArgs() == 1)
		iDuration = g_iDefaultBanTime;

	char sReason[64];
	if (g_bUseReasonMenu && IsValidClient(client))
	{
		Menu_ShowBanReasonSelection(client, target, iDuration);
		return Plugin_Handled;
	}
	else
	{
		FormatEx(sReason, sizeof(sReason), sArguments[len]);

		if (!sReason[0])
			sReason = g_sDefaultBanReason;

		TrimString(sReason);
		StripQuotes(sReason);
	}

	if (g_iMaxBanTime != 0 && iDuration > g_iMaxBanTime || iDuration < -1)
	{
		ReplyToCommand(client, "\x04[entWatch] \x01Invalid duration supplied, value must be between -1 and %d (0 = Perma, -1 = Temporary)", g_iMaxBanTime);
		return Plugin_Handled;
	}

	ClientRestrict(client, target, iDuration, sReason);

	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Handle sm_eunban command - remove restriction from client
//----------------------------------------------------------------------------------------------------
public Action Command_ClientUnrestrict(int client, int args)
{
	if (GetCmdArgs() < 1)
	{
		ReplyToCommand(client, "\x04[entWatch] \x01Usage: sm_eunban <#userid/name> [reason]");
		return Plugin_Handled;
	}

	char sArguments[2][128];
	GetCmdArg(1, sArguments[0], sizeof(sArguments[]));
	GetCmdArg(2, sArguments[1], sizeof(sArguments[]));

	int target;
	if ((target = FindTarget(client, sArguments[0], true)) == -1)
		return Plugin_Handled;

	if (!g_RestrictClients[target].bRestricted)
	{
		ReplyToCommand(client, "\x04[entWatch] \x01%N is not currently restricted", target);
		return Plugin_Handled;
	}

	if (g_bUseReasonMenu)
	{
		Menu_ShowUnbanReasonSelection(client, target);
		return Plugin_Handled;
	}

	char sReason[64];
	if (GetCmdArgs() >= 2)
	{
		FormatEx(sReason, sizeof(sReason), "%s", sArguments[1]);
		TrimString(sReason);
		StripQuotes(sReason);
	}

	if (!sReason[0])
		FormatEx(sReason, sizeof(sReason), "%s", g_sDefaultUnbanReason);

	ClientUnrestrict(client, target, sReason);

	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Display list of currently restricted clients
//----------------------------------------------------------------------------------------------------
public Action Command_DisplayRestrictions(int client, int args)
{
	char aBuf[1024];
	char aBuf2[MAX_NAME_LENGTH];

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsValidClient(i) || IsFakeClient(i))
			continue;

		if (!IsRestrictedClient(i))
			continue;

		GetClientName(i, aBuf2, sizeof(aBuf2));
		StrCat(aBuf, sizeof(aBuf), aBuf2);
		StrCat(aBuf, sizeof(aBuf), ", ");
	}

	if (strlen(aBuf))
	{
		aBuf[strlen(aBuf) - 2] = 0;
		ReplyToCommand(client, "\x04[entWatch] \x01Currently restricted clients: %s", aBuf);
	}
	else
		ReplyToCommand(client, "\x04[entWatch] \x01Currently restricted clients: none");

	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Display detailed status information for a specific client
//----------------------------------------------------------------------------------------------------
public Action Command_DisplayStatus(int client, int args)
{
	int target = client;

	if (args > 0)
	{
		char sArguments[1][32];
		GetCmdArg(1, sArguments[0], sizeof(sArguments[]));

		if ((target = FindTarget(client, sArguments[0], true)) == -1)
			return Plugin_Handled;
	}

	if (!IsValidClient(target))
	{
		ReplyToCommand(client, "\x04[entWatch] \x01Player is not valid anymore");
		return Plugin_Handled;
	}

	ReplyToCommand(client, "\x04[entWatch] \x01%N has %d total eban%s", target, g_RestrictClients[target].intTotalEbans, g_RestrictClients[target].intTotalEbans == 1 ? "" : "s");

	if (!g_RestrictClients[target].bRestricted)
	{
		ReplyToCommand(client, "\x04[entWatch] \x01%N is not currently restricted", target);
		return Plugin_Handled;
	}

	ReplyToCommand(client, "\x04[entWatch] \x01%N is currently restricted", target);
	ReplyToCommand(client, "\x04[entWatch] \x01Reason: %s", g_RestrictClients[target].szReason);

	if (!g_bDetailedStatus)
		return Plugin_Handled;

	ReplyToCommand(client, "\x04[entWatch] \x01Admin: %s (%s)", g_RestrictClients[target].szAdminName, g_RestrictClients[target].szAdminSteamID);

	char sTimeBuff[64];
	FormatTime(sTimeBuff, sizeof(sTimeBuff), NULL_STRING, g_RestrictClients[target].iTimeStamp);
	ReplyToCommand(client, "\x04[entWatch] \x01Issued: %s", sTimeBuff);

	switch (g_RestrictClients[target].iDuration)
	{
		case -1:
		{
			ReplyToCommand(client, "\x04[entWatch] \x01Duration: Temporary (Session)");
			ReplyToCommand(client, "\x04[entWatch] \x01Expires: End of session");
		}
		case 0:
		{
			ReplyToCommand(client, "\x04[entWatch] \x01Duration: Permanent");
			ReplyToCommand(client, "\x04[entWatch] \x01Expires: Never");
		}
		default:
		{
			int expireTime = g_RestrictClients[target].iTimeStamp + (g_RestrictClients[target].iDuration * 60);
			int timeLeft = expireTime - GetTime();

			if (timeLeft > 0)
			{
				char sTimeLeft[64], sExpireBuf[64];
				FormatTimeLeft(timeLeft, sTimeLeft, sizeof(sTimeLeft));
				FormatTime(sExpireBuf, sizeof(sExpireBuf), NULL_STRING, expireTime);
				ReplyToCommand(client, "\x04[entWatch] \x01Duration: %d minutes", g_RestrictClients[target].iDuration);
				ReplyToCommand(client, "\x04[entWatch] \x01Expires: %s (%s remaining)", sExpireBuf, sTimeLeft);
			}
		}
	}

	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Check if client can interact with EntWatch weapon items
//----------------------------------------------------------------------------------------------------
public bool EW_OnClientItemWeaponCanInteract(int iClient, CItem hItem)
{
	return !IsRestrictedClient(iClient);
}

//----------------------------------------------------------------------------------------------------
// Purpose: Check if client can interact with EntWatch button items
//----------------------------------------------------------------------------------------------------
public bool EW_OnClientItemButtonCanInteract(int iClient, CItemButton hItemButton)
{
	return !IsRestrictedClient(iClient);
}

//----------------------------------------------------------------------------------------------------
// Purpose: Check if client can interact with EntWatch trigger items
//----------------------------------------------------------------------------------------------------
public bool EW_OnClientItemTriggerCanInteract(int iClient, CItemTrigger hItemTrigger)
{
	return !IsRestrictedClient(iClient);
}

//----------------------------------------------------------------------------------------------------
// Purpose: szReason menus
//----------------------------------------------------------------------------------------------------
void Menu_ShowBanReasonSelection(int admin, int target, int length)
{
	Menu hMenu = new Menu(MenuHandler_BanReasonSelection);
	char sTitle[128];
	if (length == -1)
		FormatEx(sTitle, sizeof(sTitle), "EBan szReason for %N [Temporary]", target);
	else if (length == 0)
		FormatEx(sTitle, sizeof(sTitle), "EBan szReason for %N [Permanently]", target);
	else
		FormatEx(sTitle, sizeof(sTitle), "EBan szReason for %N [%d Minutes]", target, length);
	hMenu.SetTitle(sTitle);

	int targetUserId = GetClientUserId(target);

	static const char sReasons[][64] = {
		"Item misuse",
		"Trolling on purpose",
		"Throwing item away",
		"Not using an item",
		"Trimming team",
		"Not listening to leader",
		"Spamming an item",
		"Other"
	};

	char sIndex[96];
	for (int i = 0; i < sizeof(sReasons); i++)
	{
		FormatEx(sIndex, sizeof(sIndex), "%d/%d/%s", length, targetUserId, sReasons[i]);
		hMenu.AddItem(sIndex, sReasons[i]);
	}

	hMenu.Display(admin, MENU_TIME_FOREVER);
}

public int MenuHandler_BanReasonSelection(Menu hMenu, MenuAction hAction, int param1, int param2)
{
	switch (hAction)
	{
		case MenuAction_End:
			delete hMenu;
		case MenuAction_Select:
		{
			char selected[96], parts[3][96], reason[64];
			hMenu.GetItem(param2, selected, sizeof(selected));
			ExplodeString(selected, "/", parts, 3, 96);
			int length = StringToInt(parts[0]);
			int target = GetClientOfUserId(StringToInt(parts[1]));
			FormatEx(reason, sizeof(reason), "%s", parts[2]);

			if (IsValidClient(target))
				ClientRestrict(param1, target, length, reason);
			else
				PrintToChat(param1, "\x04[entWatch] \x01Player is not valid anymore.");
		}
	}
	return 0;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Display unban reason selection menu for admin
//----------------------------------------------------------------------------------------------------
void Menu_ShowUnbanReasonSelection(int admin, int target)
{
	Menu hMenu = new Menu(MenuHandler_UnbanReasonSelection);
	char sTitle[128];
	FormatEx(sTitle, sizeof(sTitle), "EUnBan szReason for %N", target);
	hMenu.SetTitle(sTitle);

	int targetUserId = GetClientUserId(target);

	static const char sUnbanReasons[][64] = {
		"Wrong target",
		"Giving another chance",
		"Bad duration",
		"Was not on purpose",
		"Other"
	};

	char sIndex[96];
	for (int i = 0; i < sizeof(sUnbanReasons); i++)
	{
		FormatEx(sIndex, sizeof(sIndex), "%d/%s", targetUserId, sUnbanReasons[i]);
		hMenu.AddItem(sIndex, sUnbanReasons[i]);
	}

	hMenu.Display(admin, MENU_TIME_FOREVER);
}

public int MenuHandler_UnbanReasonSelection(Menu hMenu, MenuAction hAction, int param1, int param2)
{
	switch (hAction)
	{
		case MenuAction_End:
			delete hMenu;
		case MenuAction_Select:
		{
			char selected[96], parts[2][96], reason[64];
			hMenu.GetItem(param2, selected, sizeof(selected));
			ExplodeString(selected, "/", parts, 2, 96);
			int target = GetClientOfUserId(StringToInt(parts[0]));
			FormatEx(reason, sizeof(reason), "%s", parts[1]);

			if (IsValidClient(target))
				ClientUnrestrict(param1, target, reason);
			else
				PrintToChat(param1, "\x04[entWatch] \x01Player is not valid anymore.");
		}
	}
	return 0;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Apply restriction to client and prevent EntWatch item access
//----------------------------------------------------------------------------------------------------
stock bool ClientRestrict(int client, int target, int iDuration, const char[] reason)
{
	if (!IsValidClient(target) || IsRestrictedClient(target))
		return false;

	if (!ValidateBanPermissions(client, iDuration))
		return false;

	char sReason[64];
	if (!reason[0])
		FormatEx(sReason, sizeof(sReason), "%s", g_sDefaultBanReason);
	else
		FormatEx(sReason, sizeof(sReason), "%s", reason);

	// Mark target as Ebanned.
	g_RestrictClients[target].bVerified = true;
	g_RestrictClients[target].bRestricted = true;
	g_RestrictClients[target].intTotalEbans++;
	g_RestrictClients[target].iTimeStamp = GetTime();
	g_RestrictClients[target].iDuration = iDuration;
	strcopy(g_RestrictClients[target].szReason, sizeof(g_RestrictClients[target].szReason), sReason);

	// Store admin info
	if (client != 0)
	{
		FormatEx(g_RestrictClients[target].szAdminName, sizeof(g_RestrictClients[target].szAdminName), "%N", client);
		GetClientAuthId(client, AuthId_Steam2, g_RestrictClients[target].szAdminSteamID, sizeof(g_RestrictClients[target].szAdminSteamID), true);
	}
	else
	{
		FormatEx(g_RestrictClients[target].szAdminName, sizeof(g_RestrictClients[target].szAdminName), EW_CONSOLE_NAME);
		FormatEx(g_RestrictClients[target].szAdminSteamID, sizeof(g_RestrictClients[target].szAdminSteamID), EW_SERVER_STEAMID);
	}

	LogBanAction(client, target, iDuration, sReason);

	Call_StartForward(g_hFwd_OnClientRestricted);
	Call_PushCell(client);
	Call_PushCell(target);
	Call_PushCell(iDuration);
	Call_PushString(sReason);
	Call_Finish();

	if (g_bDropItemOnEBan)
		DropClientItems(target);

	Database_BanClient(target, client, iDuration, sReason);

	return true;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Drop all special items from a client
//----------------------------------------------------------------------------------------------------
void DropClientItems(int client)
{
	if (!IsValidClient(client))
		return;

	if (!EW_ClientHasItem(client))
		return;

	char sClassname[32];
	for (int slot = 0; slot <= 4; slot++)
	{
		if (slot == 2)
			continue;

		int WeaponInSlot = GetPlayerWeaponSlot(client, slot);
		if (WeaponInSlot < 0 || !IsValidEntity(WeaponInSlot))
			continue;

		// Skip if not a special EntWatch item
		if (!EW_IsEntityItem(WeaponInSlot))
			continue;

		GetEntityClassname(WeaponInSlot, sClassname, sizeof(sClassname));

		// Drop the weapon and give the same weapon type back to maintain game balance
		SDKHooks_DropWeapon(client, WeaponInSlot, NULL_VECTOR, NULL_VECTOR);
		GivePlayerItem(client, sClassname);
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose: Remove restriction from client and restore EntWatch item access
//----------------------------------------------------------------------------------------------------
stock bool ClientUnrestrict(int client, int target, const char[] reason)
{
	if (!IsValidClient(target) || !IsRestrictedClient(target))
		return false;

	char sReason[64];
	if (!reason[0])
		FormatEx(sReason, sizeof(sReason), "%s", g_sDefaultUnbanReason);
	else
		FormatEx(sReason, sizeof(sReason), "%s", reason);

	g_RestrictClients[target].bRestricted = false;
	g_RestrictClients[target].iTimeStamp = 0;
	g_RestrictClients[target].iDuration = 0;
	g_RestrictClients[target].szReason[0] = '\0';

	LogBanAction(client, target, 0, sReason, false, true);

	Call_StartForward(g_hFwd_OnClientUnrestricted);
	Call_PushCell(client);
	Call_PushCell(target);
	Call_PushString(sReason);
	Call_Finish();

	Database_UnbanClient(target, client, sReason);
	return true;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Check if client is currently restricted from using EntWatch items
//----------------------------------------------------------------------------------------------------
stock bool IsRestrictedClient(int client)
{
	if (!IsValidClient(client))
		return false;

	return g_RestrictClients[client].bRestricted;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Disconnect from database and reset connection state
//----------------------------------------------------------------------------------------------------
void Database_Disconnect()
{
	if (g_hRestrictDB != null)
	{
		delete g_hRestrictDB;
		g_hRestrictDB = null;
	}
	g_eRestrictDBState = EbanDB_Disconnected;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Establish database connection with retry mechanism
//----------------------------------------------------------------------------------------------------
void Database_Connect()
{
	if (g_hRestrictDB != null && g_eRestrictDBState == EbanDB_Connected)
		return;

	if (g_eRestrictDBState == EbanDB_Connecting)
		return;

	g_eRestrictDBState = EbanDB_Connecting;
	g_iRestrictConnectLock = g_iRestrictSequence++;
	Database.Connect(Database_OnConnectionSuccess, EW_DB_NAME, g_iRestrictConnectLock);
}

//----------------------------------------------------------------------------------------------------
// Purpose: Handle successful database connection and setup tables
//----------------------------------------------------------------------------------------------------
public void Database_OnConnectionSuccess(Database db, const char[] error, any data)
{
	if (db == null)
	{
		g_eRestrictDBState = EbanDB_Wait;
		CreateTimer(g_fRestrictRetryTime, Timer_Restrict_Reconnect, _, TIMER_FLAG_NO_MAPCHANGE);
		return;
	}

	if (data != g_iRestrictConnectLock || (g_hRestrictDB != null && g_eRestrictDBState == EbanDB_Connected))
	{
		if (db)
			delete db;
		return;
	}

	g_iRestrictConnectLock = 0;
	g_eRestrictDBState = EbanDB_Connected;
	g_hRestrictDB = db;

	char sDriver[16];
	g_hRestrictDB.Driver.GetIdentifier(sDriver, sizeof(sDriver));
	g_bIsSQLite = StrEqual(sDriver, "sqlite", false);

	LogMessage("[EW-Restrictions]: Connected to database. Driver: %s", sDriver);

	Database_CreateTables();
	g_hRestrictDB.SetCharset(EW_DB_CHARSET);
}

//----------------------------------------------------------------------------------------------------
// Purpose: Timer callback to retry database connection on failure
//----------------------------------------------------------------------------------------------------
public Action Timer_Restrict_Reconnect(Handle timer, any data)
{
	g_eRestrictDBState = EbanDB_Disconnected;
	Database_Connect();
	return Plugin_Continue;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Create database tables for storing ban information
//----------------------------------------------------------------------------------------------------
void Database_CreateTables()
{
	if (!g_bIsSQLite)
	{
		Transaction createTablesTransaction = new Transaction();
		char q[2048];
		FormatEx(q, sizeof(q),
			"CREATE TABLE IF NOT EXISTS `EntWatch_Current_Eban`("
			... "`id` int(10) unsigned NOT NULL auto_increment,"
			... "`client_name` varchar(32) NOT NULL,"
			... "`client_steamid` varchar(64) NOT NULL,"
			... "`admin_name` varchar(32) NOT NULL,"
			... "`admin_steamid` varchar(64) NOT NULL,"
			... "`duration` int NOT NULL,"
			... "`timestamp_issued` int NOT NULL,"
			... "`reason` varchar(64),"
			... "`reason_unban` varchar(64),"
			... "`admin_name_unban` varchar(32),"
			... "`admin_steamid_unban` varchar(64),"
			... "`timestamp_unban` int,"
			... "PRIMARY KEY (id),"
			... "INDEX `idx_steamid_search` (`client_steamid`, `admin_steamid`),"
			... "INDEX `idx_expiry_sort` (`timestamp_issued`, `duration`))"
			... "CHARACTER SET %s COLLATE %s;", EW_DB_CHARSET, EW_DB_COLLATION);
		createTablesTransaction.AddQuery(q);

		FormatEx(q, sizeof(q),
			"CREATE TABLE IF NOT EXISTS `EntWatch_Old_Eban`("
			... "`id` int(10) unsigned NOT NULL auto_increment,"
			... "`client_name` varchar(32) NOT NULL,"
			... "`client_steamid` varchar(64) NOT NULL,"
			... "`admin_name` varchar(32) NOT NULL,"
			... "`admin_steamid` varchar(64) NOT NULL,"
			... "`duration` int NOT NULL,"
			... "`timestamp_issued` int NOT NULL,"
			... "`reason` varchar(64),"
			... "`reason_unban` varchar(64),"
			... "`admin_name_unban` varchar(32),"
			... "`admin_steamid_unban` varchar(64),"
			... "`timestamp_unban` int,"
			... "PRIMARY KEY (id),"
			... "INDEX `idx_steamid_search` (`client_steamid`, `admin_steamid`),"
			... "INDEX `idx_expiry_sort` (`timestamp_issued`, `duration`))"
			... "CHARACTER SET %s COLLATE %s;", EW_DB_CHARSET, EW_DB_COLLATION);
		createTablesTransaction.AddQuery(q);

		g_hRestrictDB.Execute(createTablesTransaction, DatabaseCallback_Success, DatabaseCallback_Error, 0, DBPrio_High);
	}
	else
	{
		Transaction createTablesTransaction = new Transaction();
		char q[1024];
		FormatEx(q, sizeof(q),
			"CREATE TABLE IF NOT EXISTS `EntWatch_Current_Eban`("
			... "`id` INTEGER PRIMARY KEY AUTOINCREMENT,"
			... "`client_name` varchar(32) NOT NULL,"
			... "`client_steamid` varchar(64) NOT NULL,"
			... "`admin_name` varchar(32) NOT NULL,"
			... "`admin_steamid` varchar(64) NOT NULL,"
			... "`duration` INTEGER NOT NULL,"
			... "`timestamp_issued` INTEGER NOT NULL,"
			... "`reason` varchar(64),"
			... "`reason_unban` varchar(64),"
			... "`admin_name_unban` varchar(32),"
			... "`admin_steamid_unban` varchar(64),"
			... "`timestamp_unban` INTEGER);");
		createTablesTransaction.AddQuery(q);

		FormatEx(q, sizeof(q), "CREATE INDEX IF NOT EXISTS `idx_steamid_search` ON `EntWatch_Current_Eban` (`client_steamid`, `admin_steamid`);");
		createTablesTransaction.AddQuery(q);

		FormatEx(q, sizeof(q), "CREATE INDEX IF NOT EXISTS `idx_expiry_sort` ON `EntWatch_Current_Eban` (`timestamp_issued`, `duration`);");
		createTablesTransaction.AddQuery(q);

		FormatEx(q, sizeof(q),
			"CREATE TABLE IF NOT EXISTS `EntWatch_Old_Eban`("
			... "`id` INTEGER PRIMARY KEY AUTOINCREMENT,"
			... "`client_name` varchar(32) NOT NULL,"
			... "`client_steamid` varchar(64) NOT NULL,"
			... "`admin_name` varchar(32) NOT NULL,"
			... "`admin_steamid` varchar(64) NOT NULL,"
			... "`duration` INTEGER NOT NULL,"
			... "`timestamp_issued` INTEGER NOT NULL,"
			... "`reason` varchar(64),"
			... "`reason_unban` varchar(64),"
			... "`admin_name_unban` varchar(32),"
			... "`admin_steamid_unban` varchar(64),"
			... "`timestamp_unban` INTEGER);");
		createTablesTransaction.AddQuery(q);

		FormatEx(q, sizeof(q), "CREATE INDEX IF NOT EXISTS `idx_expiry_sort` ON `EntWatch_Old_Eban` (`timestamp_issued`, `duration`);");
		createTablesTransaction.AddQuery(q);

		g_hRestrictDB.Execute(createTablesTransaction, DatabaseCallback_Success, DatabaseCallback_Error, 0, DBPrio_High);
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose: Update client restriction data from database on connection
//----------------------------------------------------------------------------------------------------
void Database_UpdateClientRestrictionData(int client)
{
	if (g_eRestrictDBState != EbanDB_Connected || IsFakeClient(client))
		return;

	if (g_bEbanInvalidSteamID && IsInvalidSteamID(client))
	{
		ClientRestrict(0, client, -1, "SteamID not verified");
		return;
	}

	char sSteam[64];
	GetClientAuthId(client, AuthId_Steam2, sSteam, sizeof(sSteam), true);
	char sQuery[2048];

	if (g_bIsSQLite)
	{
		// Simplified query for SQLite (no complex subqueries)
		FormatEx(sQuery, sizeof(sQuery),
			"SELECT `admin_name`, `admin_steamid`, `duration`, `timestamp_issued`, `reason`, "
			... "(SELECT COUNT(*) FROM `EntWatch_Current_Eban` WHERE `client_steamid` = '%s') + "
			... "(SELECT COUNT(*) FROM `EntWatch_Old_Eban` WHERE `client_steamid` = '%s') AS total_ebans "
			... "FROM `EntWatch_Current_Eban` "
			... "WHERE `client_steamid` = '%s' "
			... "ORDER BY `timestamp_issued` DESC LIMIT 1",
			sSteam, sSteam, sSteam);
	}
	else
	{
		// Full MySQL query with complex subqueries
		FormatEx(sQuery, sizeof(sQuery),
			"SELECT ban_data.`admin_name`, ban_data.`admin_steamid`, ban_data.`duration`, ban_data.`timestamp_issued`, ban_data.`reason`, "
			... "(SELECT COUNT(*) FROM `EntWatch_Current_Eban` WHERE `client_steamid` = '%s') + "
			... "(SELECT COUNT(*) FROM `EntWatch_Old_Eban` WHERE `client_steamid` = '%s') AS total_ebans "
			... "FROM (SELECT * FROM `EntWatch_Current_Eban` "
			... "WHERE `client_steamid` = '%s' "
			... "UNION ALL "
			... "SELECT * FROM `EntWatch_Old_Eban` "
			... "WHERE `client_steamid` = '%s' AND NOT EXISTS (SELECT 1 FROM `EntWatch_Current_Eban` "
			... "WHERE `client_steamid` = '%s')) AS ban_data "
			... "ORDER BY ban_data.`timestamp_issued` DESC LIMIT 1",
			sSteam, sSteam, sSteam, sSteam, sSteam);
	}

	g_hRestrictDB.Query(DatabaseCallback_QueryResult, sQuery, GetClientUserId(client), DBPrio_Normal);
}

//----------------------------------------------------------------------------------------------------
// Purpose: Handle database callback for client restriction data update
//----------------------------------------------------------------------------------------------------
void Database_BanClient(int target, int admin, int iDuration, const char[] reason)
{
	if (g_eRestrictDBState != EbanDB_Connected)
		return;

	char sAdminName[64], sAdminSteam[64];
	GetAdminInfo(admin, sAdminName, sizeof(sAdminName), sAdminSteam, sizeof(sAdminSteam));

	char sClientSteam[64], sClientName[64];
	GetClientAuthId(target, AuthId_Steam2, sClientSteam, sizeof(sClientSteam), true);
	GetClientName(target, sClientName, sizeof(sClientName));

	char escAdmin[129], escClient[129], escReason[129];
	g_hRestrictDB.Escape(sAdminName, escAdmin, sizeof(escAdmin));
	g_hRestrictDB.Escape(sClientName, escClient, sizeof(escClient));
	g_hRestrictDB.Escape(reason, escReason, sizeof(escReason));

	int tsIssued = GetTime();

	char query[1024];
	FormatEx(query, sizeof(query),
		"INSERT INTO `EntWatch_Current_Eban` ("
		... "`client_name`,`client_steamid`,`admin_name`,`admin_steamid`,`duration`,`timestamp_issued`,`reason`) "
		... "VALUES ('%s','%s','%s','%s',%d,%d,'%s')",
		escClient, sClientSteam, escAdmin, sAdminSteam, iDuration, tsIssued, escReason);
	g_hRestrictDB.Query(DatabaseCallback_GenericQueryResult, query, DBPrio_Normal);
}

void Database_UnbanClient(int target, int admin, const char[] reason)
{
	if (g_eRestrictDBState != EbanDB_Connected)
		return;

	char sAdminName[64], sAdminSteam[64];
	GetAdminInfo(admin, sAdminName, sizeof(sAdminName), sAdminSteam, sizeof(sAdminSteam));

	char sClientSteam[64];
	GetClientAuthId(target, AuthId_Steam2, sClientSteam, sizeof(sClientSteam), true);

	char escAdmin[129], escReason[129];
	g_hRestrictDB.Escape(sAdminName, escAdmin, sizeof(escAdmin));
	g_hRestrictDB.Escape(reason, escReason, sizeof(escReason));

	Transaction unbanTransaction = new Transaction();
	char sQuery[2048];
	FormatEx(sQuery, sizeof(sQuery),
		"INSERT INTO `EntWatch_Old_Eban` ("
		... "`client_name`,`client_steamid`,`admin_name`,`admin_steamid`,`duration`,`timestamp_issued`,`reason`,"
		... "`reason_unban`,`admin_name_unban`,`admin_steamid_unban`,`timestamp_unban`) "
		... "SELECT `client_name`,`client_steamid`,`admin_name`,`admin_steamid`,`duration`,`timestamp_issued`,`reason`,"
		... "'%s','%s','%s',%d "
		... "FROM `EntWatch_Current_Eban` WHERE `client_steamid`='%s'",
		escReason, escAdmin, sAdminSteam, GetTime(), sClientSteam);
	unbanTransaction.AddQuery(sQuery);

	FormatEx(sQuery, sizeof(sQuery), "DELETE FROM `EntWatch_Current_Eban` WHERE `client_steamid`='%s'", sClientSteam);
	unbanTransaction.AddQuery(sQuery);

	g_hRestrictDB.Execute(unbanTransaction, DatabaseCallback_Success, DatabaseCallback_Error, 0, DBPrio_Normal);
}

//----------------------------------------------------------------------------------------------------
// Purpose: Periodic timer to refresh client restrictions and cleanup expired bans
//----------------------------------------------------------------------------------------------------
public Action Timer_Restrict_Refresh(Handle timer, any data)
{
	if (g_eRestrictDBState != EbanDB_Connected)
		return Plugin_Continue;

	int iCurrentTime = GetTime();

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;

		if (!g_RestrictClients[i].bVerified)
		{
			Database_UpdateClientRestrictionData(i);
			continue;
		}

		if (!g_RestrictClients[i].bRestricted)
			continue;

		if (g_RestrictClients[i].iDuration > 0 && iCurrentTime > g_RestrictClients[i].iTimeStamp + g_RestrictClients[i].iDuration * 60)
		{
			ClientUnrestrict(0, i, "Expired");
			continue;
		}
	}

	Database_CleanupExpiredBans();

	return Plugin_Continue;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Clean up expired bans from database
//----------------------------------------------------------------------------------------------------
void Database_CleanupExpiredBans()
{
	if (g_bCleanedUpTempBans)
		return;

	g_bCleanedUpTempBans = true;

	if (g_eRestrictDBState != EbanDB_Connected)
		return;

	int currentTime = GetTime();
	char sQuery[1024];

	// Find all expired temporary bans (duration > 0) and old session bans (duration = -1, older than timeout)
	FormatEx(sQuery, sizeof(sQuery),
		"SELECT `id`, `client_steamid`, `client_name`, `admin_name`, `admin_steamid`, `duration`, `timestamp_issued`, `reason` "
		... "FROM `EntWatch_Current_Eban` "
		... "WHERE (`duration` = -1 AND `timestamp_issued` + %d < %d)", EW_SESSION_BAN_TIMEOUT, currentTime);
	g_hRestrictDB.Query(DatabaseCallback_QueryResult, sQuery, -1, DBPrio_Low);
}

//----------------------------------------------------------------------------------------------------
// Purpose: Retry cleanup operation (hardcoded 3 attempts with 10s delay)
//----------------------------------------------------------------------------------------------------
public Action Timer_RetryCleanup(Handle timer)
{
	g_iCleanupRetryAttempts++;

	if (g_iCleanupRetryAttempts >= 3)
	{
		LogError("[EW-Restrictions] Max cleanup retry attempts (3) reached. Stopping retry attempts.");
		g_iCleanupRetryAttempts = 0;
		return Plugin_Stop;
	}

	LogMessage("[EW-Restrictions] Cleanup operation failed. Retrying in 10.0 seconds (attempt %d/3)", g_iCleanupRetryAttempts);

	Database_CleanupExpiredBans();
	CreateTimer(10.0, Timer_RetryCleanup, _, TIMER_FLAG_NO_MAPCHANGE);

	return Plugin_Continue;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Unified database callback handler for success operations (transactions)
//----------------------------------------------------------------------------------------------------
public void DatabaseCallback_Success(Database db, any data, int numQueries, Handle[] results, any[] qd)
{
	// Generic success callback for transactions - no action needed
}

//----------------------------------------------------------------------------------------------------
// Purpose: Unified database callback handler for error operations (transactions)
//----------------------------------------------------------------------------------------------------
public void DatabaseCallback_Error(Database db, any data, int numQueries, const char[] error, int failIndex, any[] qd)
{
	LogError("[EW-Restrictions] Database transaction failed: %s (Failed at query %d)", error, failIndex);
}

//----------------------------------------------------------------------------------------------------
// Purpose: Unified database callback handler for individual query results with error handling with no action
//----------------------------------------------------------------------------------------------------
public void DatabaseCallback_GenericQueryResult(Database db, DBResultSet results, const char[] error, any data)
{
	if (error[0])
		LogError("[EW-Restrictions] Database query failed: %s", error);
}

//----------------------------------------------------------------------------------------------------
// Purpose: Unified database callback handler for individual query results with error handling with action
//----------------------------------------------------------------------------------------------------
public void DatabaseCallback_QueryResult(Database db, DBResultSet results, const char[] error, any data)
{
	switch (data)
	{
		case -1:
		{
			if (error[0])
			{
				LogError("[EW-Restrictions] Database query failed (Database_UpdateClientRestrictionData): %s", error);
				CreateTimer(10.0, Timer_RetryCleanup, _, TIMER_FLAG_NO_MAPCHANGE);
				return;
			}

			HandleExpiredBansCleanup(results);
		}
		default:
		{
			if (error[0])
			{
				LogError("[EW-Restrictions] Database query failed (HandleClientRestrictionUpdate): %s", error);
				return;
			}

			HandleClientRestrictionUpdate(results, data);
		}
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose: Handle client restriction update from database query
//----------------------------------------------------------------------------------------------------
void HandleClientRestrictionUpdate(DBResultSet results, any userid)
{
	int client = GetClientOfUserId(userid);
	if (!client || !IsClientInGame(client))
		return;

	bool bFound = false;
	char adminName[32], adminSteamID[64], reason[64];
	int duration = 0, ts = 0, totalEbans = 0;

	int iCurrentTime = GetTime();
	while (results.FetchRow())
	{
		results.FetchString(0, adminName, sizeof(adminName));
		results.FetchString(1, adminSteamID, sizeof(adminSteamID));
		duration = results.FetchInt(2);
		ts = results.FetchInt(3);
		results.FetchString(4, reason, sizeof(reason));
		totalEbans = results.FetchInt(5);

		int expireTime = (duration == 0) ? 0 : (ts + (duration * 60));
		bFound = (duration == 0) || (iCurrentTime < expireTime);
	}

	// Apply to local state using new structure
	g_RestrictClients[client].bVerified = true;
	g_RestrictClients[client].bRestricted = bFound;
	g_RestrictClients[client].intTotalEbans = totalEbans;

	if (bFound)
	{
		strcopy(g_RestrictClients[client].szAdminName, sizeof(g_RestrictClients[client].szAdminName), adminName);
		strcopy(g_RestrictClients[client].szAdminSteamID, sizeof(g_RestrictClients[client].szAdminSteamID), adminSteamID);
		g_RestrictClients[client].iTimeStamp = ts;
		g_RestrictClients[client].iDuration = duration;
		strcopy(g_RestrictClients[client].szReason, sizeof(g_RestrictClients[client].szReason), reason);
	}
	else
	{
		g_RestrictClients[client].szAdminName[0] = '\0';
		g_RestrictClients[client].szAdminSteamID[0] = '\0';
		g_RestrictClients[client].iTimeStamp = 0;
		g_RestrictClients[client].iDuration = 0;
		g_RestrictClients[client].szReason[0] = '\0';
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose: Handle expired bans cleanup from database query
//----------------------------------------------------------------------------------------------------
void HandleExpiredBansCleanup(DBResultSet results)
{
	Transaction cleanupTransaction = new Transaction();

	while (results.FetchRow())
	{
		int banId = results.FetchInt(0);
		char clientSteam[64], clientName[32], adminName[32], adminSteam[64], reason[64];
		int duration = results.FetchInt(5);
		int timestampIssued = results.FetchInt(6);

		results.FetchString(1, clientSteam, sizeof(clientSteam));
		results.FetchString(2, clientName, sizeof(clientName));
		results.FetchString(3, adminName, sizeof(adminName));
		results.FetchString(4, adminSteam, sizeof(adminSteam));
		results.FetchString(7, reason, sizeof(reason));

		// Move to Old_Eban with "Expired" reason
		char sQuery[2048];
		FormatEx(sQuery, sizeof(sQuery),
			"INSERT INTO `EntWatch_Old_Eban` ("
			... "`client_name`,`client_steamid`,`admin_name`,`admin_steamid`,`duration`,`timestamp_issued`,`reason`,"
			... "`reason_unban`,`admin_name_unban`,`admin_steamid_unban`,`timestamp_unban`) "
			... "VALUES ("
			... "'%s','%s','%s','%s',%d,%d,'%s','Expired','Console','SERVER',%d)",
			clientName, clientSteam, adminName, adminSteam, duration, timestampIssued, reason, GetTime());
		cleanupTransaction.AddQuery(sQuery);

		// Delete from Current_Eban
		FormatEx(sQuery, sizeof(sQuery), "DELETE FROM `EntWatch_Current_Eban` WHERE `id` = %d", banId);
		cleanupTransaction.AddQuery(sQuery);
	}

	if (results.RowCount > 0)
		g_hRestrictDB.Execute(cleanupTransaction, DatabaseCallback_Success, DatabaseCallback_Error, 0, DBPrio_Low);
	else
		delete cleanupTransaction;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Unified function to validate admin permissions for ban operations
//----------------------------------------------------------------------------------------------------
bool ValidateBanPermissions(int admin, int duration, bool isOffline = false)
{
	int maxDuration = isOffline ? g_iOfflineTimeLong : g_iAdminBanLong;

	if (duration > maxDuration && !CheckCommandAccess(admin, "sm_eban_long", ADMFLAG_ROOT))
	{
		ReplyToCommand(admin, "\x04[entWatch] \x01You don't have permission to ban for %d minutes or longer. Maximum allowed: %d minutes", duration, maxDuration - 1);
		return false;
	}

	if (duration == 0 && !CheckCommandAccess(admin, "sm_eban_perm", ADMFLAG_ROOT))
	{
		ReplyToCommand(admin, "\x04[entWatch] \x01You don't have permission to ban permanently");
		return false;
	}

	return true;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Unified function to format admin information
//----------------------------------------------------------------------------------------------------
void GetAdminInfo(int admin, char[] adminName, int nameSize, char[] adminSteamID, int steamSize)
{
	if (admin != 0)
	{
		FormatEx(adminName, nameSize, "%N", admin);
		GetClientAuthId(admin, AuthId_Steam2, adminSteamID, steamSize, true);
	}
	else
	{
		FormatEx(adminName, nameSize, EW_CONSOLE_NAME);
		FormatEx(adminSteamID, steamSize, EW_SERVER_STEAMID);
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose: Check if client index is valid and connected
//----------------------------------------------------------------------------------------------------
stock bool IsValidClient(int client)
{
	return ((1 <= client <= MaxClients) && IsClientConnected(client));
}

//----------------------------------------------------------------------------------------------------
// Purpose: Native function to restrict client from using EntWatch items
//----------------------------------------------------------------------------------------------------
public int Native_ClientRestrict(Handle hPlugin, int numParams)
{
	int admin = GetNativeCell(1);
	if (!IsValidClient(admin) || !IsClientConnected(admin))
		admin = 0;

	int target = GetNativeCell(2);
	if (!IsValidClient(target))
	{
		ThrowNativeError(SP_ERROR_PARAM, "Invalid target");
		return -1;
	}

	char sReason[64];
	GetNativeString(4, sReason, sizeof(sReason));
	return ClientRestrict(GetNativeCell(1), target, GetNativeCell(3), sReason);
}

//----------------------------------------------------------------------------------------------------
// Purpose: Native function to remove restriction from client
//----------------------------------------------------------------------------------------------------
public int Native_ClientUnrestrict(Handle hPlugin, int numParams)
{
	int admin = GetNativeCell(1);
	if (!IsValidClient(admin) || !IsClientConnected(admin))
		admin = 0;

	int target = GetNativeCell(2);
	if (!IsValidClient(target))
	{
		ThrowNativeError(SP_ERROR_PARAM, "Invalid target");
		return -1;
	}

	char sReason[64];
	GetNativeString(3, sReason, sizeof(sReason));
	return ClientUnrestrict(GetNativeCell(1), GetNativeCell(2), sReason);
}

//----------------------------------------------------------------------------------------------------
// Purpose: Native function to check if client is currently restricted
//----------------------------------------------------------------------------------------------------
public int Native_IsRestrictedClient(Handle hPlugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsValidClient(client))
	{
		ThrowNativeError(SP_ERROR_PARAM, "Invalid client");
		return -1;
	}

	return IsRestrictedClient(client);
}

//----------------------------------------------------------------------------------------------------
// Purpose: Get total ban count for a client
//----------------------------------------------------------------------------------------------------
public int Native_GetClientBanCount(Handle hPlugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsValidClient(client))
	{
		ThrowNativeError(SP_ERROR_PARAM, "Invalid client");
		return -1;
	}

	return g_RestrictClients[client].intTotalEbans;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Get detailed ban information for a client
//----------------------------------------------------------------------------------------------------
public int Native_GetClientBanInfo(Handle hPlugin, int numParams)
{
	int client = GetNativeCell(1);
	if (!IsValidClient(client))
	{
		ThrowNativeError(SP_ERROR_PARAM, "Invalid client");
		return -1;
	}

	if (!g_RestrictClients[client].bRestricted)
		return 0;

	char adminName[32];
	GetNativeString(2, adminName, sizeof(adminName));
	if (adminName[0])
		FormatEx(adminName, sizeof(adminName), "%s", g_RestrictClients[client].szAdminName);

	char adminSteamID[64];
	GetNativeString(3, adminSteamID, sizeof(adminSteamID));
	if (adminSteamID[0])
		FormatEx(adminSteamID, sizeof(adminSteamID), "%s", g_RestrictClients[client].szAdminSteamID);

	char reason[64];
	GetNativeString(4, reason, sizeof(reason));
	if (reason[0])
		FormatEx(reason, sizeof(reason), "%s", g_RestrictClients[client].szReason);

	int duration = GetNativeCell(5);
	if (duration != -1)
		duration = g_RestrictClients[client].iDuration;

	int timestampIssued = GetNativeCell(6);
	if (timestampIssued != -1)
		timestampIssued = g_RestrictClients[client].iTimeStamp;

	int totalEbans = GetNativeCell(7);
	if (totalEbans != -1)
		totalEbans = g_RestrictClients[client].intTotalEbans;

	return 1;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Unified function to add or update player in offline eban system
//----------------------------------------------------------------------------------------------------
void OfflinePlayer_TrackOrUpdate(int client, const char[] itemName, bool bIsConnecting)
{
	if (IsFakeClient(client))
		return;

	char sClientName[32];
	GetClientName(client, sClientName, sizeof(sClientName));
	char sSteamID[64];
	GetClientAuthId(client, AuthId_Steam2, sSteamID, sizeof(sSteamID), true);

	bool bFound = false;
	for (int i = 0; i < g_OfflineArray.Length; i++)
	{
		OfflinePlayerData offlinePlayer;
		g_OfflineArray.GetArray(i, offlinePlayer, sizeof(offlinePlayer));

		if (strcmp(offlinePlayer.szPlayerSteamID, sSteamID) == 0)
		{
			bFound = true;
			offlinePlayer.iUserID = GetClientUserId(client);
			FormatEx(offlinePlayer.szPlayerName, sizeof(offlinePlayer.szPlayerName), "%s", sClientName);
			FormatEx(offlinePlayer.szLastItem, sizeof(offlinePlayer.szLastItem), "%s", itemName);

			if (bIsConnecting)
			{
				// Player is connecting/reconnecting - reset timestamps
				offlinePlayer.iTimeStamp = -1;
				offlinePlayer.iTimeStampStart = -1;
			}
			// If not connecting, keep existing timestamps

			g_OfflineArray.SetArray(i, offlinePlayer, sizeof(offlinePlayer));
			break;
		}
	}

	if (!bFound)
	{
		OfflinePlayerData newOfflinePlayer;
		newOfflinePlayer.iUserID = GetClientUserId(client);
		FormatEx(newOfflinePlayer.szPlayerName, sizeof(newOfflinePlayer.szPlayerName), "%s", sClientName);
		FormatEx(newOfflinePlayer.szPlayerSteamID, sizeof(newOfflinePlayer.szPlayerSteamID), "%s", sSteamID);
		FormatEx(newOfflinePlayer.szLastItem, sizeof(newOfflinePlayer.szLastItem), "%s", itemName);

		newOfflinePlayer.iTimeStamp = -1;
		newOfflinePlayer.iTimeStampStart = -1;

		g_OfflineArray.PushArray(newOfflinePlayer, sizeof(newOfflinePlayer));
	}
}

void OfflinePlayer_OnClientDisconnect(int client)
{
	if (!IsValidClient(client) || !IsClientConnected(client) || IsFakeClient(client))
		return;

	char sClientName[32];
	GetClientName(client, sClientName, sizeof(sClientName));
	char sSteamID[64];
	GetClientAuthId(client, AuthId_Steam2, sSteamID, sizeof(sSteamID), true);

	bool bFound = false;
	int iCurrentTime = GetTime();
	for (int i = 0; i < g_OfflineArray.Length; i++)
	{
		OfflinePlayerData offlinePlayer;
		g_OfflineArray.GetArray(i, offlinePlayer, sizeof(offlinePlayer));

		if (strcmp(offlinePlayer.szPlayerSteamID, sSteamID) == 0)
		{
			bFound = true;
			FormatEx(offlinePlayer.szPlayerName, sizeof(offlinePlayer.szPlayerName), "%s", sClientName);
			offlinePlayer.iTimeStampStart = iCurrentTime;
			offlinePlayer.iTimeStamp = offlinePlayer.iTimeStampStart + g_iOfflineTimeClear * 60;
			g_OfflineArray.SetArray(i, offlinePlayer, sizeof(offlinePlayer));
			break;
		}
	}

	if (!bFound)
	{
		OfflinePlayerData newOfflinePlayer;
		newOfflinePlayer.iUserID = GetClientUserId(client);
		FormatEx(newOfflinePlayer.szPlayerName, sizeof(newOfflinePlayer.szPlayerName), "%s", sClientName);
		FormatEx(newOfflinePlayer.szPlayerSteamID, sizeof(newOfflinePlayer.szPlayerSteamID), "%s", sSteamID);
		newOfflinePlayer.iTimeStampStart = iCurrentTime;
		newOfflinePlayer.iTimeStamp = newOfflinePlayer.iTimeStampStart + g_iOfflineTimeClear * 60;
		FormatEx(newOfflinePlayer.szLastItem, sizeof(newOfflinePlayer.szLastItem), "None");
		g_OfflineArray.PushArray(newOfflinePlayer, sizeof(newOfflinePlayer));
	}
}

public void EW_OnClientItemWeaponInteract(int iClient, CItem hItem, int iInteractionType)
{
	if (iInteractionType != EW_WEAPON_INTERACTION_PICKUP)
		return;

	if (IsFakeClient(iClient))
		return;

	if (hItem.hConfig == null)
		return;

	char sItemName[32];
	hItem.hConfig.GetName(sItemName, sizeof(sItemName));
	OfflinePlayer_TrackOrUpdate(iClient, sItemName, false);
}

//----------------------------------------------------------------------------------------------------
// Purpose: Clean up expired offline player records from memory
//----------------------------------------------------------------------------------------------------
public Action Timer_OfflineEban_Cleanup(Handle timer)
{
	int currentTime = GetTime();
	for (int i = g_OfflineArray.Length - 1; i >= 0; i--)
	{
		OfflinePlayerData offlinePlayer;
		g_OfflineArray.GetArray(i, offlinePlayer, sizeof(offlinePlayer));

		if (offlinePlayer.iTimeStamp != -1 && currentTime > offlinePlayer.iTimeStamp)
			g_OfflineArray.Erase(i);
	}

	return Plugin_Continue;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Apply ban to offline player and store in database
//----------------------------------------------------------------------------------------------------
void OfflinePlayer_BanClient(OfflinePlayerData player, int admin, int duration, const char[] reason)
{
	if (g_eRestrictDBState != EbanDB_Connected)
	{
		ReplyToCommand(admin, "[EntWatch] Database is not connected, try again later.");
		return;
	}

	if (!ValidateBanPermissions(admin, duration, true))
		return;

	char sAdminName[64], sAdminSteamID[64];
	GetAdminInfo(admin, sAdminName, sizeof(sAdminName), sAdminSteamID, sizeof(sAdminSteamID));

	char sClientName[64], sClientSteamID[64];
	FormatEx(sClientName, sizeof(sClientName), "%s", player.szPlayerName);
	FormatEx(sClientSteamID, sizeof(sClientSteamID), "%s", player.szPlayerSteamID);

	char escAdmin[129], escClient[129], escReason[129];
	g_hRestrictDB.Escape(sAdminName, escAdmin, sizeof(escAdmin));
	g_hRestrictDB.Escape(sClientName, escClient, sizeof(escClient));
	g_hRestrictDB.Escape(reason, escReason, sizeof(escReason));

	int tsIssued = GetTime();

	char query[1024];
	FormatEx(query, sizeof(query),
		"INSERT INTO `EntWatch_Current_Eban` ("
		... "`client_name`,`client_steamid`,`admin_name`,`admin_steamid`,`duration`,`timestamp_issued`,`reason`) "
		... "VALUES ('%s','%s','%s','%s',%d,%d,'%s')",
		escClient, sClientSteamID, escAdmin, sAdminSteamID, duration, tsIssued, escReason);

	g_hRestrictDB.Query(DatabaseCallback_GenericQueryResult, query, 0, DBPrio_Low);

	LogBanAction(admin, -1, duration, reason, true);
}

//----------------------------------------------------------------------------------------------------
// Purpose: Display menu listing all disconnected players available for offline ban
//----------------------------------------------------------------------------------------------------
void Menu_ShowOfflinePlayerList(int client)
{
	Menu hMenu = new Menu(MenuHandler_OfflinePlayerList);
	hMenu.SetTitle("[entWatch] List of Disconnected Players");
	hMenu.ExitButton = true;

	int currentTime = GetTime();
	bool bFound = false;

	for (int i = 0; i < g_OfflineArray.Length; i++)
	{
		OfflinePlayerData offlinePlayer;
		g_OfflineArray.GetArray(i, offlinePlayer, sizeof(offlinePlayer));

		if (offlinePlayer.iTimeStamp != -1)
		{
			char sIndex[32], sItemName[64];
			int minutesAgo = (currentTime - offlinePlayer.iTimeStampStart) / 60;
			FormatEx(sItemName, sizeof(sItemName), "%s (#%i|%i min ago)", offlinePlayer.szPlayerName, offlinePlayer.iUserID, minutesAgo);
			FormatEx(sIndex, sizeof(sIndex), "%d", offlinePlayer.iUserID);
			hMenu.AddItem(sIndex, sItemName);
			bFound = true;
		}
	}

	if (!bFound)
		hMenu.AddItem("", "No disconnected players", ITEMDRAW_DISABLED);

	hMenu.Display(client, MENU_TIME_FOREVER);
}

//----------------------------------------------------------------------------------------------------
// Purpose: Display detailed information about selected offline player
//----------------------------------------------------------------------------------------------------
void Menu_ShowOfflinePlayerDetails(int client)
{
	Menu hMenu = new Menu(MenuHandler_OfflinePlayerDetails);
	hMenu.SetTitle("[entWatch] Offline Player Info: %s", g_aMenuBuffer[client].szPlayerName);
	hMenu.ExitBackButton = true;

	char text[128];
	Format(text, sizeof(text), "Player: %s #%i (%s)", g_aMenuBuffer[client].szPlayerName, g_aMenuBuffer[client].iUserID, g_aMenuBuffer[client].szPlayerSteamID);
	hMenu.AddItem("", text, ITEMDRAW_DISABLED);

	int minutesAgo = (GetTime() - g_aMenuBuffer[client].iTimeStampStart) / 60;
	Format(text, sizeof(text), "Disconnected: %i minutes ago", minutesAgo);
	hMenu.AddItem("", text, ITEMDRAW_DISABLED);

	Format(text, sizeof(text), "Last Item: %s", g_aMenuBuffer[client].szLastItem);
	hMenu.AddItem("", text, ITEMDRAW_DISABLED);
	hMenu.AddItem("", "EBan this Player");

	hMenu.Display(client, MENU_TIME_FOREVER);
}

//----------------------------------------------------------------------------------------------------
// Purpose: Display duration selection menu for offline player ban
//----------------------------------------------------------------------------------------------------
void Menu_ShowOfflinePlayerDuration(int client)
{
	Menu hMenu = new Menu(MenuHandler_OfflinePlayerDuration);
	hMenu.SetTitle("[entWatch] EBan iDuration for %s", g_aMenuBuffer[client].szPlayerName);
	hMenu.ExitBackButton = true;

	hMenu.AddItem("10",    "10 Minutes");
	hMenu.AddItem("60",    "1 Hour");
	hMenu.AddItem("1440",  "1 Day");
	hMenu.AddItem("10080", "1 Week");
	hMenu.AddItem("40320", "1 Month");
	hMenu.AddItem("0",     "Permanently");

	hMenu.Display(client, MENU_TIME_FOREVER);
}

//----------------------------------------------------------------------------------------------------
// Purpose: Display reason selection menu for offline player ban
//----------------------------------------------------------------------------------------------------
void Menu_ShowOfflinePlayerReason(int client, int duration)
{
	Menu hMenu = new Menu(MenuHandler_OfflinePlayerReason);

	if (duration == 0)
		hMenu.SetTitle("[entWatch] EBan szReason for %s [Permanent]", g_aMenuBuffer[client].szPlayerName);
	else
		hMenu.SetTitle("[entWatch] EBan szReason for %s [%i minutes]", g_aMenuBuffer[client].szPlayerName, duration);

	hMenu.ExitBackButton = true;

	hMenu.AddItem("Item misuse",             "Item misuse");
	hMenu.AddItem("Trolling on purpose",     "Trolling on purpose");
	hMenu.AddItem("Throwing item away",      "Throwing item away");
	hMenu.AddItem("Not using an item",       "Not using an item");
	hMenu.AddItem("Trimming team",           "Trimming team");
	hMenu.AddItem("Not listening to leader", "Not listening to leader");
	hMenu.AddItem("Spamming an item",        "Spamming an item");
	hMenu.AddItem("Other",                   "Other");

	hMenu.Display(client, MENU_TIME_FOREVER);
}

//----------------------------------------------------------------------------------------------------
// Purpose: Handle offline player list menu selection and navigation
//----------------------------------------------------------------------------------------------------
public int MenuHandler_OfflinePlayerList(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
			delete menu;
		case MenuAction_Select:
		{
			char sOption[32];
			menu.GetItem(param2, sOption, sizeof(sOption));
			int itemIndex = StringToInt(sOption);

			bool bFound = false;
			for (int i = 0; i < g_OfflineArray.Length; i++)
			{
				OfflinePlayerData offlinePlayer;
				g_OfflineArray.GetArray(i, offlinePlayer, sizeof(offlinePlayer));

				if (itemIndex == offlinePlayer.iUserID)
				{
					bFound = true;
					g_aMenuBuffer[param1].iUserID = offlinePlayer.iUserID;
					FormatEx(g_aMenuBuffer[param1].szPlayerName, sizeof(g_aMenuBuffer[param1].szPlayerName), "%s", offlinePlayer.szPlayerName);
					FormatEx(g_aMenuBuffer[param1].szPlayerSteamID, sizeof(g_aMenuBuffer[param1].szPlayerSteamID), "%s", offlinePlayer.szPlayerSteamID);
					g_aMenuBuffer[param1].iTimeStamp = offlinePlayer.iTimeStamp;
					g_aMenuBuffer[param1].iTimeStampStart = offlinePlayer.iTimeStampStart;
					FormatEx(g_aMenuBuffer[param1].szLastItem, sizeof(g_aMenuBuffer[param1].szLastItem), "%s", offlinePlayer.szLastItem);
					break;
				}
			}

			if (bFound)
				Menu_ShowOfflinePlayerDetails(param1);
			else
				PrintToChat(param1, "\x04[entWatch] \x01Player is no longer valid");
		}
	}
	return 0;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Handle offline player details menu navigation
//----------------------------------------------------------------------------------------------------
public int MenuHandler_OfflinePlayerDetails(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
			delete menu;
		case MenuAction_Cancel:
			if (param2 == MenuCancel_ExitBack)
				Menu_ShowOfflinePlayerList(param1);
		case MenuAction_Select:
			Menu_ShowOfflinePlayerDuration(param1);
	}
	return 0;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Handle offline player duration selection and permission validation
//----------------------------------------------------------------------------------------------------
public int MenuHandler_OfflinePlayerDuration(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
			delete menu;
		case MenuAction_Cancel:
			if (param2 == MenuCancel_ExitBack)
				Menu_ShowOfflinePlayerDetails(param1);
		case MenuAction_Select:
		{
			char sSelected[64];
			menu.GetItem(param2, sSelected, sizeof(sSelected));
			int duration = StringToInt(sSelected);

			if (ValidateBanPermissions(param1, duration, true))
				Menu_ShowOfflinePlayerReason(param1, duration);
		}
	}
	return 0;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Handle offline player reason selection and apply ban
//----------------------------------------------------------------------------------------------------
public int MenuHandler_OfflinePlayerReason(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
			delete menu;
		case MenuAction_Cancel:
			if (param2 == MenuCancel_ExitBack)
				Menu_ShowOfflinePlayerDuration(param1);
		case MenuAction_Select:
		{
			char sSelected[64], Explode_sParam[2][64], sReason[32];
			menu.GetItem(param2, sSelected, sizeof(sSelected));
			ExplodeString(sSelected, "/", Explode_sParam, 2, 64);
			int iDuration = StringToInt(Explode_sParam[0]);
			FormatEx(sReason, sizeof(sReason), "%s", Explode_sParam[1]);
			OfflinePlayer_BanClient(g_aMenuBuffer[param1], param1, iDuration, sReason);
		}
	}
	return 0;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Handle sm_eoban command - ban offline players
//----------------------------------------------------------------------------------------------------
public Action Command_ClientOfflineRestrict(int client, int args)
{
	if (IsClientConnected(client) && IsClientInGame(client))
		Menu_ShowOfflinePlayerList(client);

	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Check if client has invalid SteamID
//----------------------------------------------------------------------------------------------------
stock bool IsInvalidSteamID(int client)
{
	char sSteam[64];
	GetClientAuthId(client, AuthId_Steam2, sSteam, sizeof(sSteam), true);
	return (strncmp(sSteam[6], "ID_", 3) == 0);
}

//----------------------------------------------------------------------------------------------------
// Purpose: Format remaining time in human readable format
//----------------------------------------------------------------------------------------------------
stock void FormatTimeLeft(int lefttime, char[] TimeLeft, int maxlength)
{
	if (lefttime > -1)
	{
		if (lefttime < 60) // Less than 1 minute
			FormatEx(TimeLeft, maxlength, "%02i %s", lefttime, "Seconds");
		else if (lefttime >= 60 && lefttime < 3600) // 1 minute to 1 hour
			FormatEx(TimeLeft, maxlength, "%i %s %02i %s", lefttime / 60, "Minutes", lefttime % 60, "Seconds");
		else if (lefttime >= 3600 && lefttime < 86400) // 1 hour to 1 day
			FormatEx(TimeLeft, maxlength, "%i %s %02i %s", lefttime / 3600, "Hours", (lefttime / 60) % 60, "Minutes");
		else if (lefttime >= 86400) // 1 day or more
			FormatEx(TimeLeft, maxlength, "%i %s %02i %s", lefttime / 86400, "Days", (lefttime / 3600) % 24, "Hours");
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose: Unified function to log ban actions (including unbans)
//----------------------------------------------------------------------------------------------------
void LogBanAction(int admin, int target, int duration, const char[] reason, bool isOffline = false, bool isUnban = false)
{
	char adminName[64];
	GetAdminInfo(admin, adminName, sizeof(adminName), "", 0);

	if (isUnban)
	{
		LogAction(admin, target, "%L unrestricted %L. szReason: %s", admin, target, reason);
		PrintToChatAll("\x04[entWatch] \x01%N unrestricted %N.", admin, target);
		PrintToChatAll("\x04[entWatch] \x01Reason: %s", reason);
		return;
	}

	if (isOffline)
	{
		if (duration == 0)
		{
			LogAction(admin, -1, "\"%L\" offline restricted \"%s\" permanently. szReason: %s", admin, adminName, reason);
			PrintToChatAll("\x04[entWatch] \x01%s \x01offline restricted \x04%s \x01permanently. \x03Reason: \x01%s", adminName, adminName, reason);
		}
		else
		{
			LogAction(admin, -1, "\"%L\" offline restricted \"%s\" for %d minutes. szReason: %s", admin, adminName, duration, reason);
			PrintToChatAll("\x04[entWatch] \x01%s \x01offline restricted \x04%s \x01for \x03%d minutes. \x03Reason: \x01%s", adminName, adminName, duration, reason);
		}
	}
	else
	{
		switch (duration)
		{
			case -1:
			{
				LogAction(admin, target, "%L restricted %L temporarily. szReason: %s", admin, target, reason);
				PrintToChatAll("\x04[entWatch] \x01%N restricted %N temporarily.", admin, target);
				PrintToChatAll("\x04[entWatch] \x01Reason: %s", reason);
			}
			case 0:
			{
				LogAction(admin, target, "%L restricted %L permanently. szReason: %s", admin, target, reason);
				PrintToChatAll("\x04[entWatch] \x01%N restricted %N permanently.", admin, target);
				PrintToChatAll("\x04[entWatch] \x01Reason: %s", reason);
			}
			default:
			{
				LogAction(admin, target, "%L restricted %L for %d minutes. szReason: %s", admin, target, duration, reason);
				PrintToChatAll("\x04[entWatch] \x01%N restricted %N for %d minutes.", admin, target, duration);
				PrintToChatAll("\x04[entWatch] \x01Reason: %s", reason);
			}
		}
	}
}