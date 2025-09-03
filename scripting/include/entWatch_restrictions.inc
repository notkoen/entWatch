#if defined entWatch_restrictions_included
	#endinput
#endif

#define entWatch_restrictions_included

/**
 * Called when a client is restricted (banned)
 *
 * @param iAdmin		Admin who restricted the client (0 = Console)
 * @param iTarget		Client who was restricted
 * @param iDuration		Duration of restriction in minutes (-1 = Temporary, 0 = Permanent)
 * @param sReason		Reason for restriction
 * @noreturn
 */
forward void EW_OnClientRestricted(int iAdmin, int iTarget, int iDuration, const char[] sReason);

/**
 * Called when a client is unrestricted (unbanned)
 *
 * @param iAdmin		Admin who unrestricted the client (0 = Console)
 * @param iTarget		Client who was unrestricted
 * @param sReason		Reason for unrestriction
 * @noreturn
 */
forward void EW_OnClientUnrestricted(int iAdmin, int iTarget, const char[] sReason);

/**
 * Restrict (ban) a client
 *
 * @param iAdmin		Admin performing the restriction (0 = Console)
 * @param iTarget		Client to restrict
 * @param iDuration		Duration of restriction in minutes (-1 = Temporary, 0 = Permanent)
 * @param sReason		Reason for restriction
 * @return				True if restriction was successful, false otherwise
 */
native bool EW_ClientRestrict(int iAdmin, int iTarget, int iDuration, const char[] sReason);

/**
 * Unrestrict (unban) a client
 *
 * @param iAdmin		Admin performing the unrestriction (0 = Console)
 * @param iTarget		Client to unrestrict
 * @param sReason		Reason for unrestriction
 * @return				True if unrestriction was successful, false otherwise
 */
native bool EW_ClientUnrestrict(int iAdmin, int iTarget, const char[] sReason);

/**
 * Check if a client is currently restricted
 *
 * @param iClient		Client to check
 * @return				True if client is restricted, false otherwise
 */
native bool EW_IsRestrictedClient(int iClient);

/**
 * Get the total number of bans for a client
 *
 * @param iClient		Client to check
 * @return				Total number of bans (current + historical), -1 if client is invalid
 */
native int EW_GetClientBanCount(int iClient);

/**
 * Get detailed ban information for a client
 *
 * @param iClient		Client to check
 * @param sAdminName	Buffer to store admin name (32 chars)
 * @param sAdminSteamID	Buffer to store admin SteamID (64 chars)
 * @param sReason		Buffer to store ban reason (64 chars)
 * @param iDuration		Variable to store ban duration
 * @param iTimestampIssued	Variable to store ban timestamp
 * @param iTotalEbans	Variable to store total ban count
 * @return				1 if client is currently banned, 0 if not banned, -1 if client is invalid
 */
native int EW_GetClientBanInfo(int iClient, char[] sAdminName, char[] sAdminSteamID, char[] sReason, int &iDuration, int &iTimestampIssued, int &iTotalEbans);

/**
 * Plugin information
 */
public SharedPlugin __pl_entWatch_restrictions =
{
	name = "entWatch-restrictions",
	file = "entWatch-restrictions.smx",

	#if defined REQUIRE_PLUGIN
		required = 1
	#else
		required = 0
	#endif
};

#if !defined REQUIRE_PLUGIN
	public void __pl_entWatch_restrictions_SetNTVOptional()
	{
		MarkNativeAsOptional("EW_ClientRestrict");
		MarkNativeAsOptional("EW_ClientUnrestrict");
		MarkNativeAsOptional("EW_IsRestrictedClient");
		MarkNativeAsOptional("EW_GetClientBanCount");
		MarkNativeAsOptional("EW_GetClientBanInfo");
	}
#endif