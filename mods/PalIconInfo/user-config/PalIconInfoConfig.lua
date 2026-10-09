------------------------------------------------
-- PalIconInfoConfig
-- Version: 1.3.1
-- Date: 2026-09-10
-- Author: ikusamaou
------------------------------------------------
-- Index
--
-- 1. Changelog
-- 2. Require
-- 3. Display Mode
-- 4. Display Option
-- 5. UI Layout
--     5.1 Palpedia Number
--     5.2 Level
--     5.3 Gender
--     5.4 Rank
--     5.5 Friendship
--     5.6 Soul
--     5.7 Passive Skill
--     5.8 Talent
------------------------------------------------
------------------------------------------------
-- 1. Changelog
------------------------------------------------
-- Version 1.3.1 - 2026-09-10
-- - Added DarnMenu integration metadata for supported in-game configuration options.
-- - Added configurable Gamepad input for DisplayMode.
-- - Added an option to enable or disable Overlay display on the multi-hatch result screen.
-- - Removed the obsolete RefreshAfterCondensation option; visible Overlays are now refreshed directly after condensation.
--
-- Version 1.3.0 - 2026-09-04
-- - Added automatic config migration with backup to preserve user settings when updating the MOD.
--
-- Version 1.2.1 - 2026-09-02
-- - Added an option to enable or disable Party Pal Slot display.
-- - Added an option to disable the PalBox refresh Hook after condensation.
--
-- Version 1.2.0 - 2026-09-02
-- - Added offset X/Y for Party.
--
-- Version 1.1.1 - 2026-08-30
-- - Added Section Index
--
-- Version 1.1.0 - 2026-08-25
-- - Added optional Ability Glasses requirement for Talent display.
--
-- Version 1.0.2 - 2026-08-23
-- - Added Talent display options.
-- - Added options to hide low Talent values and replace them with a symbol.
-- - Added configurable Talent color thresholds.
-- - Added an option to replace the maximum Talent value with a symbol.
-- - Added optional automatic horizontal text scaling.
--
-- Version 1.0.0 - 2026-08-21
-- - Initial release.
------------------------------------------------

------------------------------------------------
-- 2. Require
------------------------------------------------

-- Key.lua converts key names such as F8 into the key codes used by UE4SS.
-- It is used to convert key names into key codes.
--
-- Therefore, DisplayMode does not require numeric key codes directly;
-- keys can be configured using readable names such as Key.F8.
--
-- To assign a different key, use the key name defined in Key.lua.
-- Use the corresponding key name.
local Key = require("Key")

local Config = {

    -- Changes to PalIconInfoConfig.lua are normally loaded automatically while
    -- the game is running. The default DisplayMode keyboard/Gamepad pair is also
    -- refreshed through CommonUI. Options explicitly marked as requiring a restart
    -- take effect only after restarting the game or the MOD.
    --
    -- Keyboard-only DisplayMode hotkeys use UE4SS RegisterKeyBind(), whose
    -- callbacks cannot be physically unregistered during the current game session.
    -- Config reload still applies added, changed, or removed hotkeys immediately:
    -- callbacks from old keys dispatch through the current Config and become inert
    -- when that key is no longer configured. A full game restart is required only
    -- if the underlying RegisterKeyBind callbacks themselves must be cleared.

    ------------------------------------------------
    -- 3. Display Mode
    ------------------------------------------------
    --
    -- Each key can have multiple display states (States).
    -- When the MOD starts, State 1 is used as the current state,
    -- and the contents of State 1 are displayed initially.
    --
    -- Pressing the key advances to State 2, State 3, and so on.
    -- After the last State, it returns to State 1.
    --
    -- In each state, only items set to true are displayed by that key.

    -- For example, set all items to true to display everything.
    -- Set unwanted items to false or omit them entirely.
    --
    -- Because only items set to true are displayed,
    -- the configuration can be understood as "set only the items you want to display to true."
    -- {
    --     Number = true,
    --     Level = true,
    --     Gender = true,
    --     Rank = true,
    --     Soul = true,
    --     Friendship = true,
    --     PassiveSkill = {
    --         Bar  = true,
    --         Name = true,
    --     },
    --     Talent = true,
    -- }

    -- When multiple keys are active at the same time,
    -- the true values from each key are combined.
    --
    -- For example,
    --
    -- F7 = Everything except passive skill names
    -- F8 = Passive skill names only
    --
    -- If both are active, the result is everything displayed.
    --
    -- Keys that do nothing do not need to be configured.
    ------------------------------------------------

    -- Only condensation stars are added by this mod.
    -- A single state keeps F1 / R3 from enabling other information.
    DisplayMode = {
        [Key.F1] = {
            GamepadButton = "Right Stick Press",
            { Rank = true },
        },
    },
    DisplayOption = {

        Soul = {

            -- Do not display the value when the Soul Rank is 0.
            HideZero = true, -- @darn

        },

        Friendship = {

            -- Do not display the value when Friendship Rank is 0.
            HideZero = true, -- @darn

        },

        PassiveSkill = {

            -- Sort passive skills in descending Skill Rank order.
            -- When false, use the same order as shown on the Pal details screen.
            SortBySkillRank = true, -- @darn

        },

        Talent = {

            -- Require the Ability Glasses to display Talent values.
            RequireAbilityGlasses = true, -- @darn

            -- Value at which the Talent color changes from Blue to Green.
            GreenThreshold = 70, -- @darn min=0; max=100; step=1

            -- Value at which the Talent color changes from Green to Yellow
            -- and MaxValueSymbol can be used.
            MaxThreshold = 100, -- @darn min=0; max=100; step=1

            -- Do not display the Talent value when it is
            -- below this value.
            -- 0 = Display all Talent values.
            HideValueBelow = 0, -- @darn min=0; max=100; step=1

            -- Replace Talent values below HideValueBelow with this symbol.
            -- Leave empty to display nothing.
            -- Example: "・"
            HideValueSymbol = "・", -- @darn maxlen=8

            -- Replace the Talent value 100 with this symbol.
            -- Leave empty to display 100 as usual.
            -- Example: "★"
            MaxValueSymbol = "", -- @darn maxlen=8
        },

        ------------------------------------------------
        -- Party Pal Slot Display
        ------------------------------------------------
        -- Enable or disable Overlay display for Party Pal Slots.
        --
        -- When disabled, the Party Pal Slot Hooks are not registered
        -- and no Overlay information is displayed on Party Pal Slots.
        --
        -- Changing this option requires restarting the game or the MOD.
        --
        -- true  = Enable
        -- false = Disable
        EnablePartyDisplay = true, -- @darn restart=true

        ------------------------------------------------
        -- Multi-Hatch Result Display
        ------------------------------------------------
        -- Enable or disable Overlay display on the multi-hatch result screen.
        --
        -- When disabled, the hatch-result Hooks are not registered
        -- and no Overlay information is displayed on hatch-result entries.
        --
        -- Changing this option requires restarting the game or the MOD.
        --
        -- true  = Enable
        -- false = Disable
        EnableHatchDisplay = true, -- @darn restart=true


    },


    ------------------------------------------------
    -- 5. UI Layout
    ------------------------------------------------
    --
    -- Configures the position and size of the Overlay.
    --
    -- All coordinates and sizes are specified relative to Config.UI.BaseSize.
    -- The current BaseSize is 80.
    --
    -- BaseSize is the reference size used to calculate Overlay coordinates and dimensions,
    -- and is separate from the actual Widget size on screen.
    --
    -- BaseSize / OffsetX / OffsetY define the coordinate system shared by all Overlays.
    -- Left / Top / Width / Height for each item
    -- are specified individually within this coordinate system.
    --
    -- FontSize specifies the TextBlock font size,
    -- and PitchX / PitchY specify the spacing between multiple Widgets of the same type.
    --
    -- Changing BaseSize changes the coordinate system for all Overlays,
    -- so for individual position adjustments, do not change BaseSize first;
    -- adjust the Left / Top / Width / Height of the relevant Widget instead.
    ------------------------------------------------

    UI = {

        --------------------------------------------------
        -- Coordinate System
        --------------------------------------------------

        -- Reference size for the entire Overlay.
        -- Each Widget's coordinates and size are calculated from this value.
        BaseSize = 80,

        --------------------------------------------------
        -- Overlay Position by Target
        --------------------------------------------------
        -- Reference offset used to move the entire Overlay.
        -- Adjusts the position of the entire Overlay without changing individual Widget Left / Top values.
        Normal = {

            -- Offset used for normal PalBox slots.
            OffsetX = 0, -- @darn min=-500; max=500; step=1
            OffsetY = 0, -- @darn min=-500; max=500; step=1

        },

        Party = {

            -- Offset used for Party Pal slots.
            OffsetX = 130, -- @darn min=-500; max=500; step=1
            OffsetY = -3, -- @darn min=-500; max=500; step=1

        },

        -- Vertical text-size adjustment for TextBlocks.
        -- Adjusts only the vertical height of the text independently of FontSize.
        FontHeightScale = 1.2,

        --------------------------------------------------
        -- Widget Settings
        --------------------------------------------------
        --
        -- Left / Top:
        -- Top-left position of the Widget.
        --
        -- Width / Height:
        -- Widget size.
        --
        -- FontSize:
        -- TextBlock font size.
        --
        -- TextFit:
        -- How to handle text that exceeds the Widget width.
        -- "Clip" = Clip text that exceeds the width.
        -- "AutoScale" = Automatically shrink the text to fit the width.
        --
        -- Bold:
        -- Whether to use bold text.
        --
        -- Outline:
        -- Whether to enable the text outline.
        --
        -- HAlign / VAlign:
        -- Horizontal / vertical text alignment within the TextBlock.
        --
        -- PitchX / PitchY:
        -- Spacing between multiple instances of the same Widget.
        --
        -- Color:
        -- Widget color.
        -- Specify R / G / B / A from 0.0 to 1.0.
        -- Unspecified components retain the existing Widget values in main.lua.
        --------------------------------------------------

        --------------------------------------------------
        -- 5.1 Palpedia Number
        --------------------------------------------------

        -- Settings for displaying the Palpedia number.
        -- Text_No displays the number prefix, and Text_NumberValue displays the numeric part.
        -- Text_SuffixValue displays the suffix (such as "B"), and Text_0 displays leading zeros in gray.
        Number = {

            Text_No = {

                Left   = 1,
                Top    = -3,
                Width  = 20,
                Height = 16,

                FontSize = 8,

                Bold = true,
                Outline = true,

                HAlign = "Center",
                VAlign = "Bottom",

            },

            Text_NumberValue = {

                Left   = 19,
                Top    = -4,
                Width  = 16,
                Height = 16,

                FontSize = 11,

                Bold = true,
                Outline = true,

                HAlign = "Left",
                VAlign = "Bottom",

            },

            Text_SuffixValue = {

                Left   = 45,
                Top    = 0,
                Width  = 16,
                Height = 16,

                FontSize = 8,

                Bold = true,
                Outline = true,

                HAlign = "Left",
                VAlign = "Center",

            },

            Text_0 = {

                Left   = 19,
                Top    = -4,
                Width  = 16,
                Height = 16,

                FontSize = 11,

                Bold = true,
                Outline = true,

                HAlign = "Left",
                VAlign = "Bottom",

                Color = {
                    R = 0.3,
                    G = 0.3,
                    B = 0.3,
                    A = 1
                },
            },
        },

        --------------------------------------------------
        -- 5.2 Level
        --------------------------------------------------

        -- Settings for displaying the Pal's level.
        -- Text_Lv displays the "Lv" prefix, and Text_LevelValue displays the level value.
        Level = {

            Text_Lv = {

                Left   = 19,
                Top    = -3,
                Width  = 20,
                Height = 16,

                HAlign = "Center",
                VAlign = "Bottom",
                FontSize = 8,

                Bold = true,
                Outline = true,

            },

            Text_LevelValue = {

                Left   = 40,
                Top    = -4,
                Width  = 16,
                Height = 16,

                HAlign = "Right",
                VAlign = "Bottom",
                FontSize = 11,

                Bold = true,
                Outline = true,

            },

        },


        --------------------------------------------------
        -- 5.3 Gender
        --------------------------------------------------

        -- Settings for displaying the Pal's gender icon.
        -- Image_GenderIcon displays the gender icon,
        -- and Image_GenderIconBG provides its background.
        Gender = {

            Image_GenderIcon = {

                Left   = 62,
                Top    = 66,
                Width  = 16,
                Height = 16,

            },

            Image_GenderIconBG = {

                Left   = 61,
                Top    = 65,
                Width  = 18,
                Height = 18,

                Color = {
                    R = 0,
                    G = 0,
                    B = 0,
                    A = 1
                }

            }

        },


        --------------------------------------------------
        -- 5.4 Rank
        --------------------------------------------------

        -- Settings for displaying the Condensation Rank as star icons.
        -- Multiple Image_RankIcon widgets are created, with PitchX specifying the spacing between them.
        Rank = {

            Image_RankIcon = {

                Left   = 4,
                Top    = 65,
                Width  = 18,
                Height = 18,

                PitchX = 14,

            }

        },


        --------------------------------------------------
        -- 5.5 Friendship
        --------------------------------------------------

        -- Settings for displaying Friendship Rank.
        -- Image_FriendshipIcon displays the icon,
        -- and Text_FriendshipValue displays the rank value.
        Friendship = {

            Image_FriendshipIcon = {

                Left   = -1,
                Top    = 22,
                Width  = 25,
                Height = 24,

            },

            Text_FriendshipValue = {

                Left   = 2,
                Top    = 22,
                Width  = 20,
                Height = 20,

                HAlign = "Center",
                FontSize = 10,

                Bold = true,
                Outline = true,

            },

        },


        --------------------------------------------------
        -- 5.6 Soul
        --------------------------------------------------

        -- Settings for displaying Soul Rank.
        -- Image_SoulIcon displays the icon, and Text_SoulValue displays the rank value.
        Soul = {

            Image_SoulIcon = {

                Left   = -1,
                Top    = 38,
                Width  = 25,
                Height = 25,

            },

            Text_SoulValue = {

                Left   = 2,
                Top    = 42,
                Width  = 20,
                Height = 18,

                HAlign = "Center",
                FontSize = 10,

                Bold = true,
                Outline = true,

            },

        },


        --------------------------------------------------
        -- 5.7 Passive Skill
        --------------------------------------------------

        -- Settings for displaying passive skills.
        --
        -- Bar contains the rank display icons and background,
        -- and Name contains the passive skill names and their background.
        --
        -- Up to four instances of each item are created, with PitchY specifying the spacing between rows.
        PassiveSkill = {

            Bar = {

                Image_PassiveSkillIcon = {

                    Left   = 1,
                    Top    = 7,
                    Width  = 18,
                    Height = 3,

                    PitchY = 4,

                    Color = {
                        A = 1
                    },
                },

                Image_Background = {

                    Left   = 0,
                    Top    = 6,
                    Width  = 20,
                    Height = 17,

                    Color = {
                        R = 0,
                        G = 0,
                        B = 0,
                        A = 0.5
                    }

                },

            },

            Name = {

                Text_PassiveSkillName = {

                    Left   = 2,
                    Top    = 11.5,
                    -- Set to 77 to use the full width.
                    Width  = 60,
                    Height = 16,

                    HAlign = "Left",
                    VAlign = "Center",
                    FontSize = 8,

                    Outline = true,


                    -- If you want to clip instead of using AutoScale, set it to "Clip".
                    TextFit = "AutoScale",

                    Color = {
                        A = 1
                    },

                    PitchY = 13,

                },

                Image_Background = {

                    Left   = 2,
                    Top    = 18,
                    -- Set to 77 to use the full width.
                    Width  = 58,
                    Height = 12,

                    Color = {
                        A = 0.3
                    },

                    PitchY = 13,

                },

            }

        },


        --------------------------------------------------
        -- 5.8 Talent
        --------------------------------------------------

        -- Settings for displaying individual values (Talent).
        -- Three Text_TalentValue instances are created, with PitchY specifying the spacing between rows.
        Talent = {

            Text_TalentValue = {

                Left   = 61,
                Top    = 25,
                Width  = 19,
                Height = 16,

                HAlign = "Right",
                FontSize = 10,
                Bold = true,
                Outline = true,

                -- Comment this out if you do not want to use AutoScale.
                TextFit = "AutoScale",

                PitchY = 12,

            },

        },

    },

}

return Config
