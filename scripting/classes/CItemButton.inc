#if defined entWatch_class_item_button_included
	#endinput
#endif

#define entWatch_class_item_button_included

methodmap CItemButton < StringMap
{
	public CItemButton(CConfigButton hConfigButton = null, CItem hItem = null)
	{
		StringMap stringMap = new StringMap();

		stringMap.SetValue("hConfigButton",     hConfigButton);
		stringMap.SetValue("hItem",             hItem);

		stringMap.SetValue("iButton",           INVALID_ENT_REFERENCE);
		stringMap.SetValue("iState",            EW_ENTITY_STATE_INITIAL);
		stringMap.SetValue("iCurrentUses",      0);

		stringMap.SetValue("flWaitTime",        0.0);
		stringMap.SetValue("flReadyTime",       0.0);

		return view_as<CItemButton>(stringMap);
	}

	property CConfigButton hConfigButton
	{
		public get()
		{
			CConfigButton hValue;
			if (this.GetValue("hConfigButton", hValue))
				return hValue;

			return null;
		}
		public set(CConfigButton hValue)
		{
			this.SetValue("hConfigButton", hValue);
		}
	}

	property CItem hItem
	{
		public get()
		{
			CItem hValue;
			if (this.GetValue("hItem", hValue))
				return hValue;

			return null;
		}
		public set(CItem hValue)
		{
			this.SetValue("hItem", hValue);
		}
	}

	property int iButton
	{
		public get()
		{
			int iValue;
			if (this.GetValue("iButton", iValue))
				return iValue;

			return -1;
		}
		public set(int iValue)
		{
			this.SetValue("iButton", iValue);
		}
	}

	property int iState
	{
		public get()
		{
			int iValue;
			if (this.GetValue("iState", iValue))
				return iValue;

			return -1;
		}
		public set(int iValue)
		{
			this.SetValue("iState", iValue);
		}
	}

	property int iCurrentUses
	{
		public get()
		{
			int iValue;
			if (this.GetValue("iCurrentUses", iValue))
				return iValue;

			return -1;
		}
		public set(int iValue)
		{
			this.SetValue("iCurrentUses", iValue);
		}
	}

	property float flWaitTime
	{
		public get()
		{
			float flValue;
			if (this.GetValue("flWaitTime", flValue))
				return flValue;

			return -1.0;
		}
		public set(float flValue)
		{
			this.SetValue("flWaitTime", flValue);
		}
	}

	property float flReadyTime
	{
		public get()
		{
			float flValue;
			if (this.GetValue("flReadyTime", flValue))
				return flValue;

			return -1.0;
		}
		public set(float flValue)
		{
			this.SetValue("flReadyTime", flValue);
		}
	}
}
