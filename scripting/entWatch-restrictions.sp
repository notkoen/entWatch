//====================================================================================================
//
// Name: [entWatch] Restrictions
// Author: zaCade, Prometheum, koen, Rushaway
// Description: Handle the restrictions of [entWatch]
//
//====================================================================================================

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <entWatch_core>

#define EW_DB_NAME             "EntWatch4"
#define EW_DB_CHARSET          "utf8mb4"
#define EW_DB_COLLATION        "utf8mb4_unicode_ci"
#define EW_SESSION_BAN_TIMEOUT 90
#define EW_CONSOLE_NAME        "Console"
#define EW_SERVER_STEAMID      "SERVER"

//----------------------------------------------------------------------------------------------------
// Structs
//----------------------------------------------------------------------------------------------------
enum struct ClientSettings_Restrict
{
	bool bVerified;
	bool bRestricted;
	char szAdminName[32];
	char szAdminSteamID[64];
	char szReason[64];
	int  iDuration;
	int  iIssuedAt;
	int  iExpiresAt;
	int  intTotalEbans;

	void Reset()
	{
		this.bVerified         = false;
		this.bRestricted       = false;
		this.szAdminName[0]    = '\0';
		this.szAdminSteamID[0] = '\0';
		this.szReason[0]       = '\0';
		this.iDuration         = 0;
		this.iIssuedAt         = 0;
		this.iExpiresAt        = 0;
		this.intTotalEbans     = 0;
	}
}

enum struct OfflinePlayerData
{
	char szPlayerName[32];
	char szPlayerSteamID[64];
	char szLastItem[32];
	int  iUserID;
	int  iTrackedUntil;
	int  iDisconnectedAt;
}

//----------------------------------------------------------------------------------------------------
// Globals
//----------------------------------------------------------------------------------------------------
ClientSettings_Restrict g_RestrictClients[MAXPLAYERS+1];
ArrayList               g_OfflineArray;
OfflinePlayerData       g_aMenuBuffer[MAXPLAYERS+1];

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
bool g_bUseReasonMenu = false;
bool g_bEbanInvalidSteamID = true;
bool g_bDetailedStatus = false;
bool g_bDropItemOnEBan = true;
bool g_bCleanedUpOnMapStart = false;
char g_sDefaultBanReason[64];
char g_sDefaultUnbanReason[64];
int  g_iDefaultBanTime = 0;
int  g_iAdminBanLong = 720;
int  g_iMaxBanTime = 0;
int  g_iOfflineTimeClear = 30;
int  g_iOfflineTimeLong = 720;
int  g_iCleanupRetryAttempts = 0;

/* DATABASE */
enum EbanDBState
{
	EbanDB_Disconnected = 0,
	EbanDB_Connecting,
	EbanDB_Connected,
	EbanDB_Wait
};
EbanDBState g_eDBState = EbanDB_Disconnected;
Database    g_hDB = null;
bool        g_bIsSQLite = false;
int         g_iConnectLock = 0;
int         g_iConnectSequence = 0;
float       g_fRetryTime = 15.0;

/* FORWARDS */
GlobalForward g_hFwd_OnClientRestricted;
GlobalForward g_hFwd_OnClientUnrestricted;
GlobalForward g_hFwd_OnRestrictBroadcast;
GlobalForward g_hFwd_OnUnrestrictBroadcast;
GlobalForward g_hFwd_OnOfflineRestrictBroadcast;

//----------------------------------------------------------------------------------------------------
// Purpose: Plugin info
//----------------------------------------------------------------------------------------------------
public Plugin myinfo =
{
	name        = "[entWatch] Restrictions",
	author      = "zaCade, Prometheum, koen, Rushaway",
	description = "Handle the restrictions of [entWatch]",
	version     = EW_VERSION
};

//----------------------------------------------------------------------------------------------------
// Purpose: Register natives and library
//----------------------------------------------------------------------------------------------------
public APLRes AskPluginLoad2(Handle hMyself, bool bLate, char[] sError, int errorSize)
{
	CreateNative("EW_ClientRestrict",     Native_ClientRestrict);
	CreateNative("EW_ClientUnrestrict",   Native_ClientUnrestrict);
	CreateNative("EW_IsRestrictedClient", Native_IsRestrictedClient);
	CreateNative("EW_GetClientBanCount",  Native_GetClientBanCount);
	CreateNative("EW_GetClientBanInfo",   Native_GetClientBanInfo);
	CreateNative("EW_ShowBanReasonMenu",   Native_ShowBanReasonMenu);
	CreateNative("EW_ShowUnbanReasonMenu", Native_ShowUnbanReasonMenu);

	RegPluginLibrary("entWatch-restrictions");
	g_bLate = bLate;
	return APLRes_Success;
}

//----------------------------------------------------------------------------------------------------
// Purpose: Initialize plugin, setup database and commands
//----------------------------------------------------------------------------------------------------
public void OnPluginStart()
{
	if (SQL_CheckConfig(EW_DB_NAME))
		Database_Connect();
	else
		SetFailState("Could not find \"%s\" entry in databases.cfg.", EW_DB_NAME);

	g_hFwd_OnClientRestricted         = new GlobalForward("EW_OnClientRestricted",         ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_String);
	g_hFwd_OnClientUnrestricted       = new GlobalForward("EW_OnClientUnrestricted",       ET_Ignore, Param_Cell, Param_Cell, Param_String);
	g_hFwd_OnRestrictBroadcast        = new GlobalForward("EW_OnRestrictBroadcast",        ET_Ignore, Param_Cell, Param_Cell, Param_Cell, Param_String, Param_String, Param_String);
	g_hFwd_OnUnrestrictBroadcast      = new GlobalForward("EW_OnUnrestrictBroadcast",      ET_Ignore, Param_Cell, Param_Cell, Param_String, Param_String, Param_String);
	g_hFwd_OnOfflineRestrictBroadcast = new GlobalForward("EW_OnOfflineRestrictBroadcast", ET_Ignore, Param_Cell, Param_Cell, Param_String, Param_String, Param_String, Param_String);

	g_hCVar_UseReasonMenu       = CreateConVar("sm_eban_use_reason_menu",           "0",                     "Use menu to choose reason when missing",                       _, true, 0.0, true, 1.0);
	g_hCVar_DefaultBanReason    = CreateConVar("sm_eban_default_reason",            "Item misuse",           "Default eban reason (max 64 chars)");
	g_hCVar_DefaultUnbanReason  = CreateConVar("sm_eban_default_unban_reason",      "Giving another chance", "Default e-unban reason (max 64 chars)");
	g_hCVar_DefaultBanTime      = CreateConVar("sm_eban_default_time",              "0",                     "Default eban time in minutes (-1=session, 0=permanent)",       _, true, -1.0, true, 43200.0);
	g_hCVar_AdminBanLong        = CreateConVar("sm_eban_admin_max_minutes",         "720",                   "Max eban duration (minutes) for non-root admins",              _, true, 1.0);
	g_hCVar_EbanInvalidSteamID  = CreateConVar("sm_eban_invalid_steamid_temp",      "1",                     "Temporarily eban clients with invalid SteamID",               _, true, 0.0, true, 1.0);
	g_hCVar_MaxBanTime          = CreateConVar("sm_eban_max_minutes_cmd",           "0",                     "Max minutes via console command (0=disabled)",                _, true, 0.0);
	g_hCVar_DetailedStatus      = CreateConVar("sm_eban_status_detailed",           "0",                     "Show detailed status in sm_status",                           _, true, 0.0, true, 1.0);
	g_hCVar_DropOnEBan          = CreateConVar("sm_eban_drop_items",                "1",                     "Drop entWatch items on eban",                                 _, true, 0.0, true, 1.0);
	g_hCVar_OfflineClearRecords = CreateConVar("sm_eban_offline_cache_minutes",     "30",                    "Track disconnected players for X minutes (1-240)",            _, true, 1.0, true, 240.0);
	g_hCVar_Admin_OfflineLong   = CreateConVar("sm_eban_offline_admin_max_minutes", "720",                   "Max minutes non-root admins can offline eban",                _, true, 1.0);

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

	g_bUseReasonMenu      = g_hCVar_UseReasonMenu.BoolValue;
	g_iDefaultBanTime     = g_hCVar_DefaultBanTime.IntValue;
	g_iAdminBanLong       = g_hCVar_AdminBanLong.IntValue;
	g_bEbanInvalidSteamID = g_hCVar_EbanInvalidSteamID.BoolValue;
	g_iMaxBanTime         = g_hCVar_MaxBanTime.IntValue;
	g_bDetailedStatus     = g_hCVar_DetailedStatus.BoolValue;
	g_bDropItemOnEBan     = g_hCVar_DropOnEBan.BoolValue;
	g_hCVar_DefaultBanReason.GetString(g_sDefaultBanReason, sizeof(g_sDefaultBanReason));
	g_hCVar_DefaultUnbanReason.GetString(g_sDefaultUnbanReason, sizeof(g_sDefaultUnbanReason));
	g_iOfflineTimeClear   = g_hCVar_OfflineClearRecords.IntValue;
	g_iOfflineTimeLong    = g_hCVar_Admin_OfflineLong.IntValue;

	RegAdminCmd("sm_eban",   Command_ClientRestrict,        ADMFLAG_BAN);
	RegAdminCmd("sm_eunban", Command_ClientUnrestrict,      ADMFLAG_UNBAN);
	RegAdminCmd("sm_eoban",  Command_ClientOfflineRestrict, ADMFLAG_BAN);

	RegConsoleCmd("sm_restrictions", Command_DisplayRestrictions);
	RegConsoleCmd("sm_status",       Command_DisplayStatus);

	CreateTimer(30.0, Timer_Refresh,             _, TIMER_REPEAT);
	CreateTimer(60.0, Timer_OfflineEban_Cleanup, _, TIMER_REPEAT);

	if (g_OfflineArray == null)
		g_OfflineArray = new ArrayList(sizeof(OfflinePlayerData));

	if (!g_bLate)
		return;

	for (int client = 1; client <= MaxClients; client++)
	{
		if (!IsClientConnected(client) || !IsClientInGame(client) || IsFakeClient(client))
			continue;

		OfflinePlayer_TrackOrUpdate(client, "None", true);
		Database_FetchClientBan(client);
	}
}

//----------------------------------------------------------------------------------------------------
// Purpose: Cvar change hook
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
// Purpose: Disconnect DB on unload
//----------------------------------------------------------------------------------------------------
public void OnPluginEnd()
{
	Database_Disconnect();
}

//----------------------------------------------------------------------------------------------------
// Purpose: Reset state on map change
//----------------------------------------------------------------------------------------------------
public void OnMapStart()
{
	g_bCleanedUpOnMapStart = false;
	g_iCleanupRetryAttempts = 0;
	Client_ResetAll();
}

//----------------------------------------------------------------------------------------------------
// Purpose: Start tracking player and queue DB fetch
//----------------------------------------------------------------------------------------------------
public void OnClientPostAdminCheck(int client)
{
	if (IsFakeClient(client))
		return;

	OfflinePlayer_TrackOrUpdate(client, "None", true);
	Database_FetchClientBan(client);
}

//----------------------------------------------------------------------------------------------------
// Purpose: Clean up on disconnect
//----------------------------------------------------------------------------------------------------
public void OnClientDisconnect(int client)
{
	g_RestrictClients[client].Reset();
	OfflinePlayer_OnClientDisconnect(client);
}

//----------------------------------------------------------------------------------------------------
// Purpose: Reset all in-memory restriction data and re-fetch from DB
//----------------------------------------------------------------------------------------------------
void Client_ResetAll()
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;

		g_RestrictClients[i].Reset();
		Database_FetchClientBan(i);
	}
}

//====================================================================================================
// COMMANDS
//====================================================================================================

//----------------------------------------------------------------------------------------------------
// Purpose: sm_eban — restrict a connected player
//----------------------------------------------------------------------------------------------------
public Action Command_ClientRestrict(int client, int args)
{
	if (GetCmdArgs() < 1)
	{
		ReplyToCommand(client, "Usage: sm_eban <#userid/name> [duration] [reason]");
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

	int target = FindTarget(client, sArg, true);
	if (target == -1)
		return Plugin_Handled;

	if (g_RestrictClients[target].bRestricted)
	{
		char sName[MAX_NAME_LENGTH];
		GetClientName(target, sName, sizeof(sName));
		ReplyToCommand(client, "%s is already restricted.", sName);
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

	if (iDuration < -1 || (g_iMaxBanTime != 0 && iDuration > g_iMaxBanTime))
	{
		ReplyToCommand(client, "Invalid duration. Must be -1 to %d (0=permanent, -1=session).", g_iMaxBanTime);
		return Plugin_Handled;
	}

	if (g_bUseReasonMenu && IsValidClient(client))
	{
		Menu_ShowBanReasonSelection(client, target, iDuration);
		return Plugin_Handled;
	}

	char sReason[64];
	FormatEx(sReason, sizeof(sReason), "%s", sArguments[len]);
	if (!sReason[0])
		FormatEx(sReason, sizeof(sReason), "%s", g_sDefaultBanReason);
	TrimString(sReason);
	StripQuotes(sReason);

	ClientRestrict(client, target, iDuration, sReason);
	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------
// Purpose: sm_eunban — remove restriction from a connected player
//----------------------------------------------------------------------------------------------------
public Action Command_ClientUnrestrict(int client, int args)
{
	if (GetCmdArgs() < 1)
	{
		ReplyToCommand(client, "Usage: sm_eunban <#userid/name> [reason]");
		return Plugin_Handled;
	}

	char sArg[64], sReason[64];
	GetCmdArg(1, sArg, sizeof(sArg));
	GetCmdArg(2, sReason, sizeof(sReason));

	int target = FindTarget(client, sArg, true);
	if (target == -1)
		return Plugin_Handled;

	if (!g_RestrictClients[target].bRestricted)
	{
		char sName[MAX_NAME_LENGTH];
		GetClientName(target, sName, sizeof(sName));
		ReplyToCommand(client, "%s is not currently restricted.", sName);
		return Plugin_Handled;
	}

	if (g_bUseReasonMenu && IsValidClient(client))
	{
		Menu_ShowUnbanReasonSelection(client, target);
		return Plugin_Handled;
	}

	TrimString(sReason);
	StripQuotes(sReason);
	if (!sReason[0])
		FormatEx(sReason, sizeof(sReason), "%s", g_sDefaultUnbanReason);

	ClientUnrestrict(client, target, sReason);
	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------
// Purpose: sm_restrictions — list currently restricted players
//----------------------------------------------------------------------------------------------------
public Action Command_DisplayRestrictions(int client, int args)
{
	char aBuf[1024], aName[MAX_NAME_LENGTH];

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsValidClient(i) || IsFakeClient(i) || !IsRestrictedClient(i))
			continue;

		GetClientName(i, aName, sizeof(aName));
		StrCat(aBuf, sizeof(aBuf), aName);
		StrCat(aBuf, sizeof(aBuf), ", ");
	}

	if (strlen(aBuf) > 2)
	{
		aBuf[strlen(aBuf) - 2] = '\0';
		ReplyToCommand(client, "Currently restricted: %s", aBuf);
	}
	else
		ReplyToCommand(client, "No players are currently restricted.");

	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------
// Purpose: sm_status — show restriction status for a player
//----------------------------------------------------------------------------------------------------
public Action Command_DisplayStatus(int client, int args)
{
	int target = client;
	if (args > 0)
	{
		char sArg[32];
		GetCmdArg(1, sArg, sizeof(sArg));
		target = FindTarget(client, sArg, true);
		if (target == -1)
			return Plugin_Handled;
	}

	if (!IsValidClient(target))
	{
		ReplyToCommand(client, "Player is not valid.");
		return Plugin_Handled;
	}

	char sName[MAX_NAME_LENGTH];
	GetClientName(target, sName, sizeof(sName));

	int iTotalEbans = g_RestrictClients[target].intTotalEbans;
	ReplyToCommand(client, "%s has %d total eban%s.", sName, iTotalEbans, iTotalEbans != 1 ? "s" : "");

	if (!g_RestrictClients[target].bRestricted)
	{
		ReplyToCommand(client, "%s is not currently restricted.", sName);
		return Plugin_Handled;
	}

	ReplyToCommand(client, "%s is currently restricted.", sName);
	ReplyToCommand(client, "Reason: %s", g_RestrictClients[target].szReason);

	if (!g_bDetailedStatus)
		return Plugin_Handled;

	ReplyToCommand(client, "Admin: %s (%s)", g_RestrictClients[target].szAdminName, g_RestrictClients[target].szAdminSteamID);

	char sIssuedBuf[64];
	FormatTime(sIssuedBuf, sizeof(sIssuedBuf), NULL_STRING, g_RestrictClients[target].iIssuedAt);
	ReplyToCommand(client, "Issued: %s", sIssuedBuf);

	switch (g_RestrictClients[target].iDuration)
	{
		case -1:
		{
			ReplyToCommand(client, "Duration: Temporary (Session)");
			ReplyToCommand(client, "Expires: End of session");
		}
		case 0:
		{
			ReplyToCommand(client, "Duration: Permanent");
			ReplyToCommand(client, "Expires: Never");
		}
		default:
		{
			int iTimeLeft = g_RestrictClients[target].iExpiresAt - GetTime();
			if (iTimeLeft > 0)
			{
				char sTimeLeft[64], sExpireBuf[64];
				FormatTimeLeft(iTimeLeft, sTimeLeft, sizeof(sTimeLeft));
				FormatTime(sExpireBuf, sizeof(sExpireBuf), NULL_STRING, g_RestrictClients[target].iExpiresAt);

				ReplyToCommand(client, "Duration: %d minutes", g_RestrictClients[target].iDuration);
				ReplyToCommand(client, "Expires: %s (%s remaining)", sExpireBuf, sTimeLeft);
			}
		}
	}

	return Plugin_Handled;
}

//----------------------------------------------------------------------------------------------------
// Purpose: sm_eoban — ban an offline player
//----------------------------------------------------------------------------------------------------
public Action Command_ClientOfflineRestrict(int client, int args)
{
	if (IsClientConnected(client) && IsClientInGame(client))
		Menu_ShowOfflinePlayerList(client);

	return Plugin_Handled;
}

//====================================================================================================
// ENTWATCH CORE HOOKS
//====================================================================================================

public bool EW_OnClientItemWeaponCanInteract(int iClient, CItem hItem)
{
	return !IsRestrictedClient(iClient);
}

public bool EW_OnClientItemButtonCanInteract(int iClient, CItemButton hItem)
{
	return !IsRestrictedClient(iClient);
}

public bool EW_OnClientItemTriggerCanInteract(int iClient, CItemTrigger hItem)
{
	return !IsRestrictedClient(iClient);
}

public void EW_OnClientItemWeaponInteract(int iClient, CItem hItem, int iType)
{
	if (iType != EW_WEAPON_INTERACTION_PICKUP || IsFakeClient(iClient) || hItem.hConfig == null)
		return;

	char sItemName[32];
	hItem.hConfig.GetName(sItemName, sizeof(sItemName));
	OfflinePlayer_TrackOrUpdate(iClient, sItemName, false);
}

//====================================================================================================
// CORE RESTRICT / UNRESTRICT
//====================================================================================================

stock bool ClientRestrict(int admin, int target, int iDuration, const char[] reason)
{
	if (!IsValidClient(target) || IsRestrictedClient(target))
		return false;

	if (!ValidateBanPermissions(admin, iDuration, false))
		return false;

	char sReason[64];
	FormatEx(sReason, sizeof(sReason), "%s", reason[0] ? reason : g_sDefaultBanReason);

	int iNow     = GetTime();
	int iExpires = (iDuration > 0) ? (iNow + iDuration * 60) : 0;

	g_RestrictClients[target].bVerified    = true;
	g_RestrictClients[target].bRestricted  = true;
	g_RestrictClients[target].intTotalEbans++;
	g_RestrictClients[target].iIssuedAt    = iNow;
	g_RestrictClients[target].iExpiresAt   = iExpires;
	g_RestrictClients[target].iDuration    = iDuration;
	strcopy(g_RestrictClients[target].szReason, sizeof(g_RestrictClients[target].szReason), sReason);

	char sAdminName[32], sAdminSteam[64];
	GetAdminInfo(admin, sAdminName, sizeof(sAdminName), sAdminSteam, sizeof(sAdminSteam));
	strcopy(g_RestrictClients[target].szAdminName,    sizeof(g_RestrictClients[target].szAdminName),    sAdminName);
	strcopy(g_RestrictClients[target].szAdminSteamID, sizeof(g_RestrictClients[target].szAdminSteamID), sAdminSteam);

	LogBanAction(admin, target, iDuration, sReason, false);

	Call_StartForward(g_hFwd_OnClientRestricted);
	Call_PushCell(admin);
	Call_PushCell(target);
	Call_PushCell(iDuration);
	Call_PushString(sReason);
	Call_Finish();

	if (g_bDropItemOnEBan)
		DropClientItems(target);

	if (iDuration != -1)
		Database_InsertBan(target, admin, iDuration, iNow, iExpires, sReason);

	return true;
}

stock bool ClientUnrestrict(int admin, int target, const char[] reason)
{
	if (!IsValidClient(target) || !IsRestrictedClient(target))
		return false;

	char sReason[64];
	FormatEx(sReason, sizeof(sReason), "%s", reason[0] ? reason : g_sDefaultUnbanReason);

	int iPrevDuration = g_RestrictClients[target].iDuration;

	g_RestrictClients[target].bRestricted       = false;
	g_RestrictClients[target].iIssuedAt         = 0;
	g_RestrictClients[target].iExpiresAt        = 0;
	g_RestrictClients[target].iDuration         = 0;
	g_RestrictClients[target].szReason[0]       = '\0';
	g_RestrictClients[target].szAdminName[0]    = '\0';
	g_RestrictClients[target].szAdminSteamID[0] = '\0';

	LogBanAction(admin, target, 0, sReason, true);

	Call_StartForward(g_hFwd_OnClientUnrestricted);
	Call_PushCell(admin);
	Call_PushCell(target);
	Call_PushString(sReason);
	Call_Finish();

	if (iPrevDuration != -1)
		Database_UpdateUnban(target, admin, sReason);

	return true;
}

stock bool IsRestrictedClient(int client)
{
	return IsValidClient(client) && g_RestrictClients[client].bRestricted;
}

void DropClientItems(int client)
{
	if (!IsValidClient(client) || !EW_ClientHasItem(client))
		return;

	char sClassname[32];
	for (int slot = 0; slot <= 4; slot++)
	{
		if (slot == 2)
			continue;

		int weapon = GetPlayerWeaponSlot(client, slot);
		if (weapon < 0 || !IsValidEntity(weapon) || !EW_IsEntityItem(weapon))
			continue;

		GetEntityClassname(weapon, sClassname, sizeof(sClassname));
		SDKHooks_DropWeapon(client, weapon, NULL_VECTOR, NULL_VECTOR);
		GivePlayerItem(client, sClassname);
	}
}

//====================================================================================================
// TIMERS
//====================================================================================================

public Action Timer_Refresh(Handle timer)
{
	if (g_eDBState == EbanDB_Wait)
	{
		Database_Connect();
		return Plugin_Continue;
	}

	if (g_eDBState != EbanDB_Connected)
		return Plugin_Continue;

	int iNow = GetTime();

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsClientInGame(i) || IsFakeClient(i))
			continue;

		if (!g_RestrictClients[i].bVerified)
		{
			Database_FetchClientBan(i);
			continue;
		}

		if (!g_RestrictClients[i].bRestricted)
			continue;

		if (g_RestrictClients[i].iDuration > 0 && iNow >= g_RestrictClients[i].iExpiresAt)
			ClientUnrestrict(0, i, "Expired");
	}

	if (!g_bCleanedUpOnMapStart)
		Database_CleanupExpiredBans();

	return Plugin_Continue;
}

public Action Timer_OfflineEban_Cleanup(Handle timer)
{
	int iNow = GetTime();
	for (int i = g_OfflineArray.Length - 1; i >= 0; i--)
	{
		OfflinePlayerData p;
		g_OfflineArray.GetArray(i, p, sizeof(p));
		if (p.iTrackedUntil != -1 && iNow > p.iTrackedUntil)
			g_OfflineArray.Erase(i);
	}
	return Plugin_Continue;
}

//====================================================================================================
// DATABASE
//====================================================================================================

void Database_Disconnect()
{
	delete g_hDB;
	g_eDBState = EbanDB_Disconnected;
}

void Database_Connect()
{
	if (g_hDB != null && g_eDBState == EbanDB_Connected)
		return;

	if (g_eDBState == EbanDB_Connecting)
		return;

	g_eDBState = EbanDB_Connecting;
	g_iConnectLock = g_iConnectSequence++;
	Database.Connect(Database_OnConnect, EW_DB_NAME, g_iConnectLock);
}

public void Database_OnConnect(Database db, const char[] error, any data)
{
	if (db == null)
	{
		LogError("Connection failed: %s", error);
		g_eDBState = EbanDB_Wait;
		CreateTimer(g_fRetryTime, Timer_Reconnect, _, TIMER_FLAG_NO_MAPCHANGE);
		return;
	}

	if (data != g_iConnectLock || (g_hDB != null && g_eDBState == EbanDB_Connected))
	{
		delete db;
		return;
	}

	g_iConnectLock = 0;
	g_eDBState     = EbanDB_Connected;
	g_hDB          = db;

	char sDriver[16];
	g_hDB.Driver.GetIdentifier(sDriver, sizeof(sDriver));
	g_bIsSQLite = StrEqual(sDriver, "sqlite", false);

	LogMessage("Connected. Driver: %s", sDriver);

	g_hDB.SetCharset(EW_DB_CHARSET);
	Database_CreateTable();
}

public Action Timer_Reconnect(Handle timer, any data)
{
	g_eDBState = EbanDB_Disconnected;
	Database_Connect();
	return Plugin_Continue;
}

void Database_CreateTable()
{
	char sQuery[2048];
	Transaction tx = new Transaction();

	if (!g_bIsSQLite)
	{
		FormatEx(sQuery, sizeof(sQuery),
			"CREATE TABLE IF NOT EXISTS `EntWatch_Ebans` ("
			... "`id`                  INT UNSIGNED NOT NULL AUTO_INCREMENT,"
			... "`client_name`         VARCHAR(32)  NOT NULL,"
			... "`client_steamid`      VARCHAR(64)  NOT NULL,"
			... "`admin_name`          VARCHAR(32)  NOT NULL,"
			... "`admin_steamid`       VARCHAR(64)  NOT NULL,"
			... "`duration_minutes`    INT          NOT NULL,"
			... "`issued_at`           INT          NOT NULL,"
			... "`expires_at`          INT          NULL,"
			... "`reason`              VARCHAR(64)  NULL,"
			... "`unbanned_at`         INT          NULL,"
			... "`unban_reason`        VARCHAR(64)  NULL,"
			... "`unban_admin_name`    VARCHAR(32)  NULL,"
			... "`unban_admin_steamid` VARCHAR(64)  NULL,"
			... "PRIMARY KEY (`id`),"
			... "INDEX `idx_client`  (`client_steamid`),"
			... "INDEX `idx_active`  (`unbanned_at`, `expires_at`),"
			... "INDEX `idx_expires` (`expires_at`)"
			... ") CHARACTER SET %s COLLATE %s;",
			EW_DB_CHARSET, EW_DB_COLLATION);
		tx.AddQuery(sQuery);
	}
	else
	{
		FormatEx(sQuery, sizeof(sQuery),
			"CREATE TABLE IF NOT EXISTS `EntWatch_Ebans` ("
			... "`id`                  INTEGER PRIMARY KEY AUTOINCREMENT,"
			... "`client_name`         VARCHAR(32)  NOT NULL,"
			... "`client_steamid`      VARCHAR(64)  NOT NULL,"
			... "`admin_name`          VARCHAR(32)  NOT NULL,"
			... "`admin_steamid`       VARCHAR(64)  NOT NULL,"
			... "`duration_minutes`    INTEGER      NOT NULL,"
			... "`issued_at`           INTEGER      NOT NULL,"
			... "`expires_at`          INTEGER      NULL,"
			... "`reason`              VARCHAR(64)  NULL,"
			... "`unbanned_at`         INTEGER      NULL,"
			... "`unban_reason`        VARCHAR(64)  NULL,"
			... "`unban_admin_name`    VARCHAR(32)  NULL,"
			... "`unban_admin_steamid` VARCHAR(64)  NULL"
			... ");");
		tx.AddQuery(sQuery);

		FormatEx(sQuery, sizeof(sQuery), "CREATE INDEX IF NOT EXISTS `idx_client`  ON `EntWatch_Ebans` (`client_steamid`);");
		tx.AddQuery(sQuery);
		FormatEx(sQuery, sizeof(sQuery), "CREATE INDEX IF NOT EXISTS `idx_active`  ON `EntWatch_Ebans` (`unbanned_at`, `expires_at`);");
		tx.AddQuery(sQuery);
		FormatEx(sQuery, sizeof(sQuery), "CREATE INDEX IF NOT EXISTS `idx_expires` ON `EntWatch_Ebans` (`expires_at`);");
		tx.AddQuery(sQuery);
	}

	g_hDB.Execute(tx, DB_OnTableCreated, DB_OnError, 0, DBPrio_High);
}

public void DB_OnTableCreated(Database db, any data, int numQueries, Handle[] results, any[] qd)
{
	LogMessage("Table ready.");
	Client_ResetAll();
	Database_CleanupExpiredBans();
}

void Database_FetchClientBan(int client)
{
	if (g_eDBState != EbanDB_Connected || IsFakeClient(client))
		return;

	if (g_bEbanInvalidSteamID && IsInvalidSteamID(client))
	{
		ClientRestrict(0, client, -1, "SteamID not verified");
		return;
	}

	char sSteam[64], sQuery[1024];
	GetClientAuthId(client, AuthId_Steam2, sSteam, sizeof(sSteam), true);

	FormatEx(sQuery, sizeof(sQuery),
		"SELECT `admin_name`, `admin_steamid`, `duration_minutes`, `issued_at`, `expires_at`, `reason`,"
		... " (SELECT COUNT(*) FROM `EntWatch_Ebans` WHERE `client_steamid` = '%s') AS total_ebans"
		... " FROM `EntWatch_Ebans`"
		... " WHERE `client_steamid` = '%s'"
		... "   AND `unbanned_at` IS NULL"
		... "   AND (`expires_at` IS NULL OR `expires_at` > %d)"
		... " ORDER BY `issued_at` DESC LIMIT 1",
		sSteam, sSteam, GetTime());

	g_hDB.Query(DB_OnFetchClientBan, sQuery, GetClientUserId(client), DBPrio_Normal);
}

public void DB_OnFetchClientBan(Database db, DBResultSet results, const char[] error, any userid)
{
	if (error[0])
	{
		LogError("FetchClientBan failed: %s", error);
		return;
	}

	int client = GetClientOfUserId(userid);
	if (!client || !IsClientInGame(client))
		return;

	g_RestrictClients[client].bVerified = true;

	if (!results.FetchRow())
	{
		g_RestrictClients[client].bRestricted       = false;
		g_RestrictClients[client].szAdminName[0]    = '\0';
		g_RestrictClients[client].szAdminSteamID[0] = '\0';
		g_RestrictClients[client].szReason[0]       = '\0';
		g_RestrictClients[client].iDuration         = 0;
		g_RestrictClients[client].iIssuedAt         = 0;
		g_RestrictClients[client].iExpiresAt        = 0;
		return;
	}

	char adminName[32], adminSteam[64], reason[64];
	results.FetchString(0, adminName, sizeof(adminName));
	results.FetchString(1, adminSteam, sizeof(adminSteam));
	int iDuration   = results.FetchInt(2);
	int iIssuedAt   = results.FetchInt(3);
	int iExpiresAt  = results.IsFieldNull(4) ? 0 : results.FetchInt(4);
	results.FetchString(5, reason, sizeof(reason));
	int iTotalEbans = results.FetchInt(6);

	g_RestrictClients[client].bRestricted    = true;
	g_RestrictClients[client].iDuration      = iDuration;
	g_RestrictClients[client].iIssuedAt      = iIssuedAt;
	g_RestrictClients[client].iExpiresAt     = iExpiresAt;
	g_RestrictClients[client].intTotalEbans  = iTotalEbans;
	strcopy(g_RestrictClients[client].szAdminName,    sizeof(g_RestrictClients[client].szAdminName),    adminName);
	strcopy(g_RestrictClients[client].szAdminSteamID, sizeof(g_RestrictClients[client].szAdminSteamID), adminSteam);
	strcopy(g_RestrictClients[client].szReason,       sizeof(g_RestrictClients[client].szReason),       reason);
}

void Database_InsertBan(int target, int admin, int iDuration, int iIssuedAt, int iExpiresAt, const char[] reason)
{
	if (g_eDBState != EbanDB_Connected)
		return;

	char sAdminName[32], sAdminSteam[64], sClientName[32], sClientSteam[64];
	GetAdminInfo(admin, sAdminName, sizeof(sAdminName), sAdminSteam, sizeof(sAdminSteam));
	GetClientName(target, sClientName, sizeof(sClientName));
	GetClientAuthId(target, AuthId_Steam2, sClientSteam, sizeof(sClientSteam), true);

	char escAdminName[65], escClientName[65], escReason[129];
	g_hDB.Escape(sAdminName,  escAdminName,  sizeof(escAdminName));
	g_hDB.Escape(sClientName, escClientName, sizeof(escClientName));
	g_hDB.Escape(reason,      escReason,     sizeof(escReason));

	char sQuery[1024];
	if (iExpiresAt > 0)
	{
		FormatEx(sQuery, sizeof(sQuery),
			"INSERT INTO `EntWatch_Ebans` "
			... "(`client_name`,`client_steamid`,`admin_name`,`admin_steamid`,`duration_minutes`,`issued_at`,`expires_at`,`reason`) "
			... "VALUES ('%s','%s','%s','%s',%d,%d,%d,'%s')",
			escClientName, sClientSteam, escAdminName, sAdminSteam, iDuration, iIssuedAt, iExpiresAt, escReason);
	}
	else
	{
		FormatEx(sQuery, sizeof(sQuery),
			"INSERT INTO `EntWatch_Ebans` "
			... "(`client_name`,`client_steamid`,`admin_name`,`admin_steamid`,`duration_minutes`,`issued_at`,`expires_at`,`reason`) "
			... "VALUES ('%s','%s','%s','%s',%d,%d,NULL,'%s')",
			escClientName, sClientSteam, escAdminName, sAdminSteam, iDuration, iIssuedAt, escReason);
	}

	g_hDB.Query(DB_OnGenericError, sQuery, 0, DBPrio_Normal);
}

void Database_UpdateUnban(int target, int admin, const char[] reason)
{
	if (g_eDBState != EbanDB_Connected)
		return;

	char sAdminName[32], sAdminSteam[64], sClientSteam[64];
	GetAdminInfo(admin, sAdminName, sizeof(sAdminName), sAdminSteam, sizeof(sAdminSteam));
	GetClientAuthId(target, AuthId_Steam2, sClientSteam, sizeof(sClientSteam), true);

	char escAdminName[65], escReason[129];
	g_hDB.Escape(sAdminName, escAdminName, sizeof(escAdminName));
	g_hDB.Escape(reason,     escReason,    sizeof(escReason));

	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery),
		"UPDATE `EntWatch_Ebans`"
		... " SET `unbanned_at`=%d, `unban_reason`='%s', `unban_admin_name`='%s', `unban_admin_steamid`='%s'"
		... " WHERE `client_steamid`='%s' AND `unbanned_at` IS NULL"
		... " ORDER BY `issued_at` DESC LIMIT 1",
		GetTime(), escReason, escAdminName, sAdminSteam, sClientSteam);

	g_hDB.Query(DB_OnGenericError, sQuery, 0, DBPrio_Normal);
}

void Database_CleanupExpiredBans()
{
	if (g_eDBState != EbanDB_Connected)
		return;

	g_bCleanedUpOnMapStart = true;

	int  iNow = GetTime();
	char sQuery[512];

	FormatEx(sQuery, sizeof(sQuery),
		"UPDATE `EntWatch_Ebans`"
		... " SET `unbanned_at`=%d, `unban_reason`='Expired', `unban_admin_name`='%s', `unban_admin_steamid`='%s'"
		... " WHERE `unbanned_at` IS NULL"
		... "   AND ("
		...     "(`duration_minutes` = -1 AND `issued_at` + %d < %d)"
		...     " OR "
		...     "(`expires_at` IS NOT NULL AND `expires_at` < %d)"
		...   ")",
		iNow, EW_CONSOLE_NAME, EW_SERVER_STEAMID,
		EW_SESSION_BAN_TIMEOUT, iNow,
		iNow);

	g_hDB.Query(DB_OnCleanupResult, sQuery, 0, DBPrio_Low);
}

public void DB_OnCleanupResult(Database db, DBResultSet results, const char[] error, any data)
{
	if (!error[0])
		return;

	LogError("Cleanup query failed: %s", error);

	g_bCleanedUpOnMapStart = false;
	g_iCleanupRetryAttempts++;

	if (g_iCleanupRetryAttempts >= 3)
	{
		LogError("Cleanup failed 3 times. Giving up until next map.");
		g_iCleanupRetryAttempts = 0;
		g_bCleanedUpOnMapStart  = true;
		return;
	}

	CreateTimer(10.0, Timer_RetryCleanup, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_RetryCleanup(Handle timer)
{
	Database_CleanupExpiredBans();
	return Plugin_Stop;
}

public void DB_OnSuccess(Database db, any data, int numQueries, Handle[] results, any[] qd)
{
	// Do nothing yet
}

public void DB_OnError(Database db, any data, int numQueries, const char[] error, int failIndex, any[] qd)
{
	LogError("Transaction failed at query %d: %s", failIndex, error);
}

public void DB_OnGenericError(Database db, DBResultSet results, const char[] error, any data)
{
	if (error[0])
		LogError("Query failed: %s", error);
}

//====================================================================================================
// OFFLINE BAN SYSTEM
//====================================================================================================

void OfflinePlayer_TrackOrUpdate(int client, const char[] itemName, bool bIsConnecting)
{
	if (IsFakeClient(client))
		return;

	char sName[32], sSteam[64];
	GetClientName(client, sName, sizeof(sName));
	GetClientAuthId(client, AuthId_Steam2, sSteam, sizeof(sSteam), true);

	for (int i = 0; i < g_OfflineArray.Length; i++)
	{
		OfflinePlayerData p;
		g_OfflineArray.GetArray(i, p, sizeof(p));
		if (!StrEqual(p.szPlayerSteamID, sSteam))
			continue;

		p.iUserID = GetClientUserId(client);
		strcopy(p.szPlayerName, sizeof(p.szPlayerName), sName);
		strcopy(p.szLastItem,   sizeof(p.szLastItem),   itemName);
		if (bIsConnecting)
		{
			p.iTrackedUntil   = -1;
			p.iDisconnectedAt = -1;
		}
		g_OfflineArray.SetArray(i, p, sizeof(p));
		return;
	}

	OfflinePlayerData newP;
	newP.iUserID         = GetClientUserId(client);
	newP.iTrackedUntil   = -1;
	newP.iDisconnectedAt = -1;
	strcopy(newP.szPlayerName,    sizeof(newP.szPlayerName),    sName);
	strcopy(newP.szPlayerSteamID, sizeof(newP.szPlayerSteamID), sSteam);
	strcopy(newP.szLastItem,      sizeof(newP.szLastItem),      itemName);
	g_OfflineArray.PushArray(newP, sizeof(newP));
}

void OfflinePlayer_OnClientDisconnect(int client)
{
	if (!IsValidClient(client) || IsFakeClient(client))
		return;

	char sName[32], sSteam[64];
	GetClientName(client, sName, sizeof(sName));
	GetClientAuthId(client, AuthId_Steam2, sSteam, sizeof(sSteam), true);

	int iNow = GetTime();

	for (int i = 0; i < g_OfflineArray.Length; i++)
	{
		OfflinePlayerData p;
		g_OfflineArray.GetArray(i, p, sizeof(p));
		if (!StrEqual(p.szPlayerSteamID, sSteam))
			continue;

		strcopy(p.szPlayerName, sizeof(p.szPlayerName), sName);
		p.iDisconnectedAt = iNow;
		p.iTrackedUntil   = iNow + g_iOfflineTimeClear * 60;
		g_OfflineArray.SetArray(i, p, sizeof(p));
		return;
	}

	OfflinePlayerData newP;
	newP.iUserID         = GetClientUserId(client);
	newP.iDisconnectedAt = iNow;
	newP.iTrackedUntil   = iNow + g_iOfflineTimeClear * 60;
	strcopy(newP.szPlayerName,    sizeof(newP.szPlayerName),    sName);
	strcopy(newP.szPlayerSteamID, sizeof(newP.szPlayerSteamID), sSteam);
	strcopy(newP.szLastItem,      sizeof(newP.szLastItem),      "None");
	g_OfflineArray.PushArray(newP, sizeof(newP));
}

void OfflinePlayer_BanClient(OfflinePlayerData player, int admin, int iDuration, const char[] reason)
{
	if (g_eDBState != EbanDB_Connected)
	{
		ReplyToCommand(admin, "Database is not connected.");
		return;
	}

	if (!ValidateBanPermissions(admin, iDuration, true))
		return;

	char sAdminName[32], sAdminSteam[64];
	GetAdminInfo(admin, sAdminName, sizeof(sAdminName), sAdminSteam, sizeof(sAdminSteam));

	char escAdmin[65], escClient[65], escReason[129];
	g_hDB.Escape(sAdminName,          escAdmin,  sizeof(escAdmin));
	g_hDB.Escape(player.szPlayerName, escClient, sizeof(escClient));
	g_hDB.Escape(reason,              escReason, sizeof(escReason));

	int iNow     = GetTime();
	int iExpires = (iDuration > 0) ? (iNow + iDuration * 60) : 0;

	char sQuery[1024];
	if (iExpires > 0)
	{
		FormatEx(sQuery, sizeof(sQuery),
			"INSERT INTO `EntWatch_Ebans` "
			... "(`client_name`,`client_steamid`,`admin_name`,`admin_steamid`,`duration_minutes`,`issued_at`,`expires_at`,`reason`) "
			... "VALUES ('%s','%s','%s','%s',%d,%d,%d,'%s')",
			escClient, player.szPlayerSteamID, escAdmin, sAdminSteam, iDuration, iNow, iExpires, escReason);
	}
	else
	{
		FormatEx(sQuery, sizeof(sQuery),
			"INSERT INTO `EntWatch_Ebans` "
			... "(`client_name`,`client_steamid`,`admin_name`,`admin_steamid`,`duration_minutes`,`issued_at`,`expires_at`,`reason`) "
			... "VALUES ('%s','%s','%s','%s',%d,%d,NULL,'%s')",
			escClient, player.szPlayerSteamID, escAdmin, sAdminSteam, iDuration, iNow, escReason);
	}

	g_hDB.Query(DB_OnGenericError, sQuery, 0, DBPrio_Low);

	Call_StartForward(g_hFwd_OnOfflineRestrictBroadcast);
	Call_PushCell(admin);
	Call_PushCell(iDuration);
	Call_PushString(reason);
	Call_PushString(sAdminName);
	Call_PushString(player.szPlayerName);
	Call_PushString(player.szPlayerSteamID);
	Call_Finish();

	if (iDuration == 0)
	{
		LogAction(admin, -1, "\"%L\" offline restricted \"%s\" (%s) permanently. Reason: %s",
			admin, player.szPlayerName, player.szPlayerSteamID, reason);
	}
	else
	{
		LogAction(admin, -1, "\"%L\" offline restricted \"%s\" (%s) for %d minutes. Reason: %s",
			admin, player.szPlayerName, player.szPlayerSteamID, iDuration, reason);
	}
}

//====================================================================================================
// MENUS
//====================================================================================================

void Menu_ShowBanReasonSelection(int admin, int target, int iDuration)
{
	Menu hMenu = new Menu(MenuHandler_BanReasonSelection);

	char sName[MAX_NAME_LENGTH], sTitle[128];
	GetClientName(target, sName, sizeof(sName));

	if (iDuration == -1)
		FormatEx(sTitle, sizeof(sTitle), "Restrict %s (Session)", sName);
	else if (iDuration == 0)
		FormatEx(sTitle, sizeof(sTitle), "Restrict %s (Permanent)", sName);
	else
		FormatEx(sTitle, sizeof(sTitle), "Restrict %s (%d min)", sName, iDuration);

	hMenu.SetTitle(sTitle);

	static const char sReasonKeys[][64] =
	{
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
	int targetUserId = GetClientUserId(target);

	for (int i = 0; i < sizeof(sReasonKeys); i++)
	{
		FormatEx(sIndex, sizeof(sIndex), "%d/%d/%s", iDuration, targetUserId, sReasonKeys[i]);
		hMenu.AddItem(sIndex, sReasonKeys[i]);
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
			char selected[96], parts[3][96];
			hMenu.GetItem(param2, selected, sizeof(selected));
			ExplodeString(selected, "/", parts, 3, 96);

			int iDuration = StringToInt(parts[0]);
			int target    = GetClientOfUserId(StringToInt(parts[1]));

			if (IsValidClient(target))
				ClientRestrict(param1, target, iDuration, parts[2]);
			else
				ReplyToCommand(param1, "Player is no longer valid.");
		}
	}
	return 0;
}

void Menu_ShowUnbanReasonSelection(int admin, int target)
{
	Menu hMenu = new Menu(MenuHandler_UnbanReasonSelection);

	char sName[MAX_NAME_LENGTH], sTitle[128];
	GetClientName(target, sName, sizeof(sName));
	FormatEx(sTitle, sizeof(sTitle), "Unrestrict %s", sName);
	hMenu.SetTitle(sTitle);

	static const char sReasonKeys[][64] =
	{
		"Wrong target",
		"Giving another chance",
		"Bad duration",
		"Was not on purpose",
		"Other"
	};

	char sIndex[96];
	int targetUserId = GetClientUserId(target);

	for (int i = 0; i < sizeof(sReasonKeys); i++)
	{
		FormatEx(sIndex, sizeof(sIndex), "%d/%s", targetUserId, sReasonKeys[i]);
		hMenu.AddItem(sIndex, sReasonKeys[i]);
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
			char selected[96], parts[2][96];
			hMenu.GetItem(param2, selected, sizeof(selected));
			ExplodeString(selected, "/", parts, 2, 96);

			int target = GetClientOfUserId(StringToInt(parts[0]));
			if (IsValidClient(target))
				ClientUnrestrict(param1, target, parts[1]);
			else
				ReplyToCommand(param1, "Player is no longer valid.");
		}
	}
	return 0;
}

void Menu_ShowOfflinePlayerList(int client)
{
	Menu hMenu = new Menu(MenuHandler_OfflinePlayerList);
	hMenu.SetTitle("Offline Players");
	hMenu.ExitButton = true;

	int  iNow   = GetTime();
	bool bFound = false;

	for (int i = 0; i < g_OfflineArray.Length; i++)
	{
		OfflinePlayerData p;
		g_OfflineArray.GetArray(i, p, sizeof(p));
		if (p.iTrackedUntil == -1)
			continue;

		char sIndex[16], sDisplay[64];
		int minsAgo = (iNow - p.iDisconnectedAt) / 60;
		FormatEx(sDisplay, sizeof(sDisplay), "%s #%d (%d min ago)", p.szPlayerName, p.iUserID, minsAgo);
		FormatEx(sIndex, sizeof(sIndex), "%d", p.iUserID);
		hMenu.AddItem(sIndex, sDisplay);
		bFound = true;
	}

	if (!bFound)
		hMenu.AddItem("", "No offline players tracked.", ITEMDRAW_DISABLED);

	hMenu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_OfflinePlayerList(Menu menu, MenuAction action, int param1, int param2)
{
	switch (action)
	{
		case MenuAction_End:
			delete menu;
		case MenuAction_Select:
		{
			char sOption[16];
			menu.GetItem(param2, sOption, sizeof(sOption));
			int iUserID = StringToInt(sOption);

			for (int i = 0; i < g_OfflineArray.Length; i++)
			{
				OfflinePlayerData p;
				g_OfflineArray.GetArray(i, p, sizeof(p));
				if (p.iUserID != iUserID)
					continue;

				g_aMenuBuffer[param1] = p;
				Menu_ShowOfflinePlayerDetails(param1);
				return 0;
			}
			ReplyToCommand(param1, "Player is no longer tracked.");
		}
	}
	return 0;
}

void Menu_ShowOfflinePlayerDetails(int client)
{
	Menu hMenu = new Menu(MenuHandler_OfflinePlayerDetails);
	hMenu.ExitBackButton = true;

	char sTitle[128], sText[128];

	FormatEx(sTitle, sizeof(sTitle), "Details: %s", g_aMenuBuffer[client].szPlayerName);
	hMenu.SetTitle(sTitle);

	FormatEx(sText, sizeof(sText), "Name: %s (#%d)", g_aMenuBuffer[client].szPlayerName, g_aMenuBuffer[client].iUserID);
	hMenu.AddItem("", sText, ITEMDRAW_DISABLED);

	FormatEx(sText, sizeof(sText), "SteamID: %s", g_aMenuBuffer[client].szPlayerSteamID);
	hMenu.AddItem("", sText, ITEMDRAW_DISABLED);

	int minsAgo = (GetTime() - g_aMenuBuffer[client].iDisconnectedAt) / 60;
	FormatEx(sText, sizeof(sText), "Disconnected: %d min ago", minsAgo);
	hMenu.AddItem("", sText, ITEMDRAW_DISABLED);

	FormatEx(sText, sizeof(sText), "Last item: %s", g_aMenuBuffer[client].szLastItem);
	hMenu.AddItem("", sText, ITEMDRAW_DISABLED);

	hMenu.AddItem("ban", "Restrict this player");

	hMenu.Display(client, MENU_TIME_FOREVER);
}

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

void Menu_ShowOfflinePlayerDuration(int client)
{
	Menu hMenu = new Menu(MenuHandler_OfflinePlayerDuration);
	hMenu.ExitBackButton = true;

	char sTitle[128];
	FormatEx(sTitle, sizeof(sTitle), "Duration for %s", g_aMenuBuffer[client].szPlayerName);
	hMenu.SetTitle(sTitle);

	hMenu.AddItem("10",    "10 minutes");
	hMenu.AddItem("60",    "1 hour");
	hMenu.AddItem("1440",  "1 day");
	hMenu.AddItem("10080", "1 week");
	hMenu.AddItem("40320", "1 month");
	hMenu.AddItem("0",     "Permanent");

	hMenu.Display(client, MENU_TIME_FOREVER);
}

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
			char sSelected[16];
			menu.GetItem(param2, sSelected, sizeof(sSelected));
			int iDuration = StringToInt(sSelected);
			if (ValidateBanPermissions(param1, iDuration, true))
				Menu_ShowOfflinePlayerReason(param1, iDuration);
		}
	}
	return 0;
}

void Menu_ShowOfflinePlayerReason(int client, int iDuration)
{
	Menu hMenu = new Menu(MenuHandler_OfflinePlayerReason);
	hMenu.ExitBackButton = true;

	char sTitle[128], sIndex[96];

	if (iDuration == 0)
		FormatEx(sTitle, sizeof(sTitle), "Reason (Permanent) for %s", g_aMenuBuffer[client].szPlayerName);
	else
		FormatEx(sTitle, sizeof(sTitle), "Reason (%d min) for %s", iDuration, g_aMenuBuffer[client].szPlayerName);
	hMenu.SetTitle(sTitle);

	static const char sReasonKeys[][64] =
	{
		"Item misuse",
		"Trolling on purpose",
		"Throwing item away",
		"Not using an item",
		"Trimming team",
		"Not listening to leader",
		"Spamming an item",
		"Other"
	};

	for (int i = 0; i < sizeof(sReasonKeys); i++)
	{
		FormatEx(sIndex, sizeof(sIndex), "%d/%s", iDuration, sReasonKeys[i]);
		hMenu.AddItem(sIndex, sReasonKeys[i]);
	}

	hMenu.Display(client, MENU_TIME_FOREVER);
}

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
			char sSelected[96], parts[2][96];
			menu.GetItem(param2, sSelected, sizeof(sSelected));
			ExplodeString(sSelected, "/", parts, 2, 96);
			int iDuration = StringToInt(parts[0]);
			OfflinePlayer_BanClient(g_aMenuBuffer[param1], param1, iDuration, parts[1]);
		}
	}
	return 0;
}

//====================================================================================================
// NATIVES
//====================================================================================================

public int Native_ClientRestrict(Handle hPlugin, int numParams)
{
	int admin = GetNativeCell(1);
	if (!IsValidClient(admin))
		admin = 0;

	int target = GetNativeCell(2);
	if (!IsValidClient(target))
	{
		ThrowNativeError(SP_ERROR_PARAM, "Invalid target");
		return -1;
	}

	char sReason[64];
	GetNativeString(4, sReason, sizeof(sReason));
	return ClientRestrict(admin, target, GetNativeCell(3), sReason);
}

public int Native_ClientUnrestrict(Handle hPlugin, int numParams)
{
	int admin = GetNativeCell(1);
	if (!IsValidClient(admin))
		admin = 0;

	int target = GetNativeCell(2);
	if (!IsValidClient(target))
	{
		ThrowNativeError(SP_ERROR_PARAM, "Invalid target");
		return -1;
	}

	char sReason[64];
	GetNativeString(3, sReason, sizeof(sReason));
	return ClientUnrestrict(admin, target, sReason);
}

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

	SetNativeString(2,  g_RestrictClients[client].szAdminName,    GetNativeCell(3));
	SetNativeString(4,  g_RestrictClients[client].szAdminSteamID, GetNativeCell(5));
	SetNativeString(6,  g_RestrictClients[client].szReason,       GetNativeCell(7));
	SetNativeCellRef(8, g_RestrictClients[client].iDuration);
	SetNativeCellRef(9, g_RestrictClients[client].iIssuedAt);
	SetNativeCellRef(10, g_RestrictClients[client].intTotalEbans);

	return 1;
}

public int Native_ShowBanReasonMenu(Handle hPlugin, int numParams)
{
	int admin = GetNativeCell(1);
	if (!IsValidClient(admin))
	{
		ThrowNativeError(SP_ERROR_PARAM, "Invalid admin (must be a connected client)");
		return 0;
	}

	int target = GetNativeCell(2);
	if (!IsValidClient(target))
	{
		ThrowNativeError(SP_ERROR_PARAM, "Invalid target");
		return 0;
	}

	int iDuration = GetNativeCell(3);
	if (iDuration < -1)
	{
		ThrowNativeError(SP_ERROR_PARAM, "Invalid duration (must be >= -1)");
		return 0;
	}

	if (g_RestrictClients[target].bRestricted)
		return 0;

	Menu_ShowBanReasonSelection(admin, target, iDuration);
	return 1;
}

public int Native_ShowUnbanReasonMenu(Handle hPlugin, int numParams)
{
	int admin = GetNativeCell(1);
	if (!IsValidClient(admin))
	{
		ThrowNativeError(SP_ERROR_PARAM, "Invalid admin (must be a connected client)");
		return 0;
	}

	int target = GetNativeCell(2);
	if (!IsValidClient(target))
	{
		ThrowNativeError(SP_ERROR_PARAM, "Invalid target");
		return 0;
	}

	if (!g_RestrictClients[target].bRestricted)
		return 0;

	Menu_ShowUnbanReasonSelection(admin, target);
	return 1;
}

//====================================================================================================
// HELPERS
//====================================================================================================

bool ValidateBanPermissions(int admin, int iDuration, bool bIsOffline)
{
	int iMax = bIsOffline ? g_iOfflineTimeLong : g_iAdminBanLong;

	if (iDuration > iMax && !CheckCommandAccess(admin, "sm_eban_long", ADMFLAG_ROOT))
	{
		ReplyToCommand(admin, "You don't have permission to ban for %d+ minutes (max: %d).", iDuration, iMax);
		return false;
	}

	if (iDuration == 0 && !CheckCommandAccess(admin, "sm_eban_perm", ADMFLAG_ROOT))
	{
		ReplyToCommand(admin, "You don't have permission to ban permanently.");
		return false;
	}

	return true;
}

void GetAdminInfo(int admin, char[] sName, int nameSize, char[] sSteam, int steamSize)
{
	if (admin != 0 && IsValidClient(admin))
	{
		FormatEx(sName, nameSize, "%N", admin);
		if (steamSize > 0)
			GetClientAuthId(admin, AuthId_Steam2, sSteam, steamSize, true);
	}
	else
	{
		FormatEx(sName,  nameSize,  EW_CONSOLE_NAME);
		if (steamSize > 0)
			FormatEx(sSteam, steamSize, EW_SERVER_STEAMID);
	}
}

void LogBanAction(int admin, int target, int iDuration, const char[] reason, bool bIsUnban)
{
	char sAdminName[MAX_NAME_LENGTH], sTargetName[MAX_NAME_LENGTH];
	char sDummySteam[1];
	GetAdminInfo(admin, sAdminName, sizeof(sAdminName), sDummySteam, sizeof(sDummySteam));
	GetClientName(target, sTargetName, sizeof(sTargetName));

	if (bIsUnban)
	{
		LogAction(admin, target, "\"%L\" unrestricted \"%L\". Reason: %s", admin, target, reason);

		Call_StartForward(g_hFwd_OnUnrestrictBroadcast);
		Call_PushCell(admin);
		Call_PushCell(target);
		Call_PushString(reason);
		Call_PushString(sAdminName);
		Call_PushString(sTargetName);
		Call_Finish();
		return;
	}

	switch (iDuration)
	{
		case -1:
			LogAction(admin, target, "\"%L\" restricted \"%L\" temporarily. Reason: %s", admin, target, reason);
		case 0:
			LogAction(admin, target, "\"%L\" restricted \"%L\" permanently. Reason: %s", admin, target, reason);
		default:
			LogAction(admin, target, "\"%L\" restricted \"%L\" for %d minutes. Reason: %s", admin, target, iDuration, reason);
	}

	Call_StartForward(g_hFwd_OnRestrictBroadcast);
	Call_PushCell(admin);
	Call_PushCell(target);
	Call_PushCell(iDuration);
	Call_PushString(reason);
	Call_PushString(sAdminName);
	Call_PushString(sTargetName);
	Call_Finish();
}

stock void FormatTimeLeft(int iSeconds, char[] sBuffer, int maxlen)
{
	if (iSeconds < 60)
		FormatEx(sBuffer, maxlen, "%d second%s", iSeconds, iSeconds != 1 ? "s" : "");
	else if (iSeconds < 3600)
		FormatEx(sBuffer, maxlen, "%d min %d sec", iSeconds / 60, iSeconds % 60);
	else if (iSeconds < 86400)
		FormatEx(sBuffer, maxlen, "%d hr %d min", iSeconds / 3600, (iSeconds / 60) % 60);
	else
		FormatEx(sBuffer, maxlen, "%d day%s %d hr", iSeconds / 86400, (iSeconds / 86400) != 1 ? "s" : "", (iSeconds / 3600) % 24);
}

stock bool IsValidClient(int client)
{
	return (1 <= client <= MaxClients) && IsClientConnected(client);
}

stock bool IsInvalidSteamID(int client)
{
	char sSteam[64];
	GetClientAuthId(client, AuthId_Steam2, sSteam, sizeof(sSteam), true);
	return strncmp(sSteam[6], "ID_", 3) == 0;
}
