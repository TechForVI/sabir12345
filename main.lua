require "import"
import "android.widget.*"
import "android.view.*"
import "android.content.*"
import "android.os.*"
import "java.io.File"
import "android.database.sqlite.SQLiteDatabase"
import "android.content.ContentValues"
import "android.text.TextUtils"
import "android.view.inputmethod.InputMethodManager"
import "android.graphics.Typeface"
import "android.app.AlertDialog"
import "android.content.Intent"
import "android.net.Uri"

-- ==================== کانٹیکسٹ چیک (مکمل طور پر درست) ====================
local ctx = activity
if not ctx then
    ctx = service
end
if not ctx then
    ctx = this
end
if not ctx then
    -- آخری آپشن کے طور پر Application Context لیں
    ctx = luajava.bindClass("android.app.ActivityThread"):currentApplication():getApplicationContext()
end
if not ctx then
    print("Error: No valid context found")
    return
end

local backupPath = "/sdcard/Download/My Clipboard Manager Backup/"
local dbFile = backupPath .. "storage.db"

local folder = File(backupPath)
if not folder.exists() then folder.mkdirs() end

-- ==================== گوگل لگ ان کنفیگریشن ====================
local client_id = "241806017107-1r55qsfqod0san52pnpngu3oejm4acd2.apps.googleusercontent.com"
local redirect_uri = "https://google-backup-server-habv.vercel.app/api"

-- ==================== پیجینیشن ویری ایبلز ====================
local ITEMS_PER_PAGE = 1000
local currentOffset = 0
local favCurrentOffset = 0
local allClipboardData = {}
local allFavoriteData = {}

-- ==================== ڈیٹا بیس انیشیلائزیشن ====================
local function initDB()
    local d = SQLiteDatabase.openOrCreateDatabase(dbFile, nil)
    d.execSQL("CREATE TABLE IF NOT EXISTS clipboard_history (id INTEGER PRIMARY KEY AUTOINCREMENT, content TEXT UNIQUE, time DATETIME DEFAULT CURRENT_TIMESTAMP)")
    d.execSQL("CREATE TABLE IF NOT EXISTS favorite_history (id INTEGER PRIMARY KEY AUTOINCREMENT, content TEXT UNIQUE, time DATETIME DEFAULT CURRENT_TIMESTAMP)")
    d.execSQL("CREATE TABLE IF NOT EXISTS user_info (id INTEGER PRIMARY KEY AUTOINCREMENT, user_name TEXT, user_email TEXT, login_time DATETIME DEFAULT CURRENT_TIMESTAMP)")
    d.execSQL("CREATE TABLE IF NOT EXISTS access_tokens (id INTEGER PRIMARY KEY AUTOINCREMENT, access_token TEXT UNIQUE, refresh_token TEXT, token_time DATETIME DEFAULT CURRENT_TIMESTAMP)")
    d.close()
end
initDB()

-- ==================== یوزر انفو سیو کریں ====================
local function saveUserInfo(name, email)
    local d = SQLiteDatabase.openOrCreateDatabase(dbFile, nil)
    d.delete("user_info", nil, nil)
    local values = ContentValues()
    values.put("user_name", name)
    values.put("user_email", email)
    d.insert("user_info", nil, values)
    d.close()
end

-- ==================== ایکسیس ٹوکن سیو کریں ====================
local function saveAccessToken(access_token, refresh_token)
    local d = SQLiteDatabase.openOrCreateDatabase(dbFile, nil)
    d.delete("access_tokens", nil, nil)
    local values = ContentValues()
    values.put("access_token", access_token)
    if refresh_token and refresh_token ~= "" then
        values.put("refresh_token", refresh_token)
    end
    d.insert("access_tokens", nil, values)
    d.close()
end

-- ==================== یوزر انفو لوڈ کریں ====================
local function getUserInfo()
    local d = SQLiteDatabase.openOrCreateDatabase(dbFile, nil)
    local cursor = d.rawQuery("SELECT user_name, user_email FROM user_info ORDER BY id DESC LIMIT 1", nil)
    local name, email = nil, nil
    if cursor and cursor.getCount() > 0 then
        cursor.moveToFirst()
        if not cursor.isNull(0) then name = cursor.getString(0) end
        if not cursor.isNull(1) then email = cursor.getString(1) end
    end
    if cursor then cursor.close() end
    d.close()
    return name, email
end

-- ==================== لاگ آؤٹ ====================
local function logout()
    local d = SQLiteDatabase.openOrCreateDatabase(dbFile, nil)
    d.delete("user_info", nil, nil)
    d.delete("access_tokens", nil, nil)
    d.close()
    
    Toast.makeText(ctx, "Logged out successfully", Toast.LENGTH_SHORT).show()
    if btnUser then
        btnUser.setText("USER NAME")
    end
end

-- ==================== مینوئل ٹوکن سیو ====================
local function saveManualTokens(input, loginDialog)
    local access, refresh, name, email = input:match("([^|]+)|([^|]*)|([^|]*)|([^|]*)")
    
    if access then
        -- ٹوکن سیو کریں
        saveAccessToken(access, refresh or "")
        
        -- یوزر انفو سیو کریں
        if name and name ~= "" then
            saveUserInfo(name, email or "")
        end
        
        -- کامیابی کا میسیج
        Toast.makeText(ctx, "✓ Login Successful!", Toast.LENGTH_SHORT).show()
        
        -- یوزر بٹن اپڈیٹ کریں
        if name and name ~= "" and btnUser then
            btnUser.setText(name)
        end
        
        -- لاگ ان ڈائیلاگ بند کریں
        if loginDialog then
            loginDialog.dismiss()
        end
    else
        Toast.makeText(ctx, "Invalid Key Format", Toast.LENGTH_LONG).show()
    end
end

-- ==================== لاگ ان ڈائیلاگ ====================
local function showLoginDialog()
    if not ctx then return end
    
    local loginLayout = {
        LinearLayout,
        orientation = "vertical",
        padding = "20dp",
        layout_width = "match_parent",
        {
            TextView,
            text = "Google Drive Login",
            textSize = "20sp",
            textColor = "#2196F3",
            gravity = "center",
            layout_marginBottom = "20dp"
        },
        {
            Button,
            id = "loginBtnGetToken",
            text = "GET ACCESS TOKEN",
            layout_width = "match_parent",
            backgroundColor = "#4CAF50",
            textColor = "#FFFFFF",
            layout_marginBottom = "15dp"
        },
        {
            EditText,
            id = "loginEtToken",
            hint = "Paste your token here...",
            layout_width = "match_parent",
            layout_marginBottom = "20dp",
            padding = "12dp",
            backgroundColor = "#F5F5F5",
            singleLine = true
        },
        {
            LinearLayout,
            orientation = "horizontal",
            layout_width = "match_parent",
            gravity = "center",
            {
                Button,
                id = "loginBtnCancel",
                text = "GO BACK",
                layout_weight = 1,
                layout_marginRight = "5dp",
                backgroundColor = "#F44336",
                textColor = "#FFFFFF",
                padding = "12dp"
            },
            {
                Button,
                id = "loginBtnLogin",
                text = "LOGIN",
                layout_weight = 1,
                layout_marginLeft = "5dp",
                backgroundColor = "#2196F3",
                textColor = "#FFFFFF",
                padding = "12dp"
            }
        }
    }
    
    local loginDialog = LuaDialog(ctx)
    loginDialog.setTitle("Login Required")
    loginDialog.setView(loadlayout(loginLayout))
    
    loginBtnGetToken.onClick = function()
        loginDialog.dismiss()
        
        local scopes = "https://www.googleapis.com/auth/drive.file " .. 
                       "https://www.googleapis.com/auth/userinfo.profile " .. 
                       "https://www.googleapis.com/auth/userinfo.email"
                       
        local auth_url = "https://accounts.google.com/o/oauth2/v2/auth?"..
                         "client_id="..client_id..
                         "&redirect_uri="..Uri.encode(redirect_uri)..
                         "&response_type=code"..
                         "&scope="..Uri.encode(scopes)..
                         "&access_type=offline"..
                         "&prompt=consent"
        
        ctx.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(auth_url)))
    end
    
    loginBtnLogin.onClick = function()
        local token_data = tostring(loginEtToken.getText()):gsub("%s+", "")
        if #token_data > 20 then
            saveManualTokens(token_data, loginDialog)
        else
            Toast.makeText(ctx, "Please enter a valid token", Toast.LENGTH_SHORT).show()
        end
    end
    
    loginBtnCancel.onClick = function()
        loginDialog.dismiss()
    end
    
    loginDialog.show()
end

-- ==================== آئٹم لے آؤٹ ====================
local item_layout = {
    LinearLayout,
    layout_width = "match_parent",
    layout_height = "wrap_content",
    {
        TextView,
        id = "text_item",
        layout_width = "match_parent",
        layout_height = "wrap_content",
        padding = "16dp",
        textSize = "16sp",
        textColor = "#212121",
        singleLine = true,
        ellipsize = "end"
    }
}

-- ==================== مین لے آؤٹ ====================
local mainLayout = {
    LinearLayout,
    orientation = "vertical",
    padding = "10dp",
    layout_width = "match_parent",
    layout_height = "match_parent",
    -- ٹاپ لیفٹ میں USER NAME بٹن
    {
        LinearLayout,
        layout_width = "match_parent",
        orientation = "horizontal",
        layout_marginBottom = "5dp",
        {
            Button,
            id = "btnUser",
            text = "USER NAME",
            textSize = "12sp",
            layout_width = "wrap_content",
            layout_height = "40dp",
            backgroundColor = "#607D8B",
            textColor = "#FFFFFF"
        },
        -- خالی جگہ بھرنے کے لیے
        {
            View,
            layout_width = "0dp",
            layout_height = "1dp",
            layout_weight = 1
        }
    },
    -- سرچ باکس
    {
        EditText,
        id = "mainEtSearch",
        hint = "Type to search...",
        layout_width = "match_parent",
        layout_height = "wrap_content",
        visibility = "gone",
        backgroundColor = "#FFFFFF",
        padding = "10dp",
        textSize = "16sp",
        singleLine = true
    },
    -- کی ورڈ بٹن
    {
        Button,
        id = "btnKeyword",
        text = "ENTER KEYWORD",
        layout_width = "match_parent",
        layout_height = "wrap_content",
        backgroundColor = "#2196F3",
        textColor = "#FFFFFF"
    },
    -- لسٹ
    {
        ListView,
        id = "lvClipboard",
        layout_width = "match_parent",
        layout_height = "0dp",
        layout_weight = 1,
        dividerHeight = "1dp",
        backgroundColor = "#F5F5F5"
    },
    -- لوڈ مور بٹن
    {
        Button,
        id = "btnLoadMore",
        text = "LOAD MORE ITEMS",
        layout_width = "match_parent",
        layout_height = "wrap_content",
        backgroundColor = "#4CAF50",
        textColor = "#FFFFFF",
        textSize = "14sp",
        visibility = "gone",
        layout_marginTop = "5dp",
        layout_marginBottom = "5dp"
    },
    -- کینسل بٹن (سرچ کے وقت)
    {
        Button,
        id = "mainBtnSearchCancel",
        text = "CANCEL",
        layout_width = "match_parent",
        layout_height = "wrap_content",
        visibility = "gone",
        backgroundColor = "#F44336",
        textColor = "#FFFFFF"
    },
    -- مین بٹن کنٹینر (4 بٹن)
    {
        LinearLayout,
        id = "mainButtonsContainer",
        layout_width = "match_parent",
        layout_height = "wrap_content",
        orientation = "horizontal",
        {
            Button,
            text = "Backup and restore",
            id = "btnBackupRestore",
            layout_weight = 1,
            backgroundColor = "#4CAF50",
            textColor = "#FFFFFF"
        },
        {
            Button,
            text = "ABOUT AND SUPPORT",
            id = "btnAbout",
            layout_weight = 1,
            backgroundColor = "#9C27B0",
            textColor = "#FFFFFF"
        },
        {
            Button,
            text = "EXIT",
            id = "btnExit",
            layout_weight = 1,
            backgroundColor = "#F44336",
            textColor = "#FFFFFF"
        },
        {
            Button,
            text = "FAVORITE",
            id = "btnFav",
            layout_weight = 1,
            backgroundColor = "#FF9800",
            textColor = "#FFFFFF"
        }
    }
}

local dlg = LuaDialog(ctx)
dlg.setTitle("My Clipboard Manager")
dlg.setView(loadlayout(mainLayout))

-- مین ایڈاپٹر
local mainAdapter = LuaAdapter(ctx, {}, item_layout)
lvClipboard.setAdapter(mainAdapter)

-- ==================== کلپ بورڈ مانیٹرنگ ====================
local function getClipText()
    if not ctx then return nil end
    local manager = ctx.getSystemService(Context.CLIPBOARD_SERVICE)
    if manager and manager.hasPrimaryClip() then
        local clip = manager.getPrimaryClip()
        if clip and clip.getItemCount() > 0 then
            local item = clip.getItemAt(0)
            if item and item.getText() then 
                return tostring(item.getText())
            end
        end
    end
    return nil
end

-- ==================== مزید کلپ بورڈ ڈیٹا لوڈ کریں ====================
local function loadMoreClipboardData(reset)
    if reset then
        currentOffset = 0
        mainAdapter.clear()
    end
    
    local startIndex = currentOffset + 1
    local endIndex = math.min(currentOffset + ITEMS_PER_PAGE, #allClipboardData)
    
    if startIndex <= endIndex then
        for i = startIndex, endIndex do
            if allClipboardData[i] then
                mainAdapter.add(allClipboardData[i])
            end
        end
    end
    
    currentOffset = endIndex
    local hasMoreItems = (currentOffset < #allClipboardData)
    
    if hasMoreItems then
        btnLoadMore.setVisibility(View.VISIBLE)
    else
        btnLoadMore.setVisibility(View.GONE)
    end
    
    mainAdapter.notifyDataSetChanged()
end

-- ==================== تمام ڈیٹا کیش لوڈ کریں ====================
local function loadAllDataToCache()
    task(function(dbFile)
        require "import"
        import "android.database.sqlite.SQLiteDatabase"
        local clipData = {}
        local favData = {}
        
        local d = SQLiteDatabase.openOrCreateDatabase(dbFile, nil)
        local cursor = d.rawQuery("SELECT content FROM clipboard_history ORDER BY id DESC", nil)
        if cursor and cursor.getCount() > 0 then
            cursor.moveToFirst()
            while not cursor.isAfterLast() do
                if not cursor.isNull(0) then
                    local content = cursor.getString(0)
                    if content and content ~= "" then
                        table.insert(clipData, tostring(content))
                    end
                end
                cursor.moveToNext()
            end
        end
        if cursor then cursor.close() end
        
        cursor = d.rawQuery("SELECT content FROM favorite_history ORDER BY id DESC", nil)
        if cursor and cursor.getCount() > 0 then
            cursor.moveToFirst()
            while not cursor.isAfterLast() do
                if not cursor.isNull(0) then
                    local content = cursor.getString(0)
                    if content and content ~= "" then
                        table.insert(favData, tostring(content))
                    end
                end
                cursor.moveToNext()
            end
        end
        if cursor then cursor.close() end
        
        d.close()
        return {clip = clipData, fav = favData}
    end, dbFile, function(data)
        allClipboardData = {}
        allFavoriteData = {}
        
        if data and data.clip then
            for i = 1, #data.clip do
                local text = data.clip[i]
                if text then
                    table.insert(allClipboardData, {text_item = text})
                end
            end
        end
        
        if data and data.fav then
            for i = 1, #data.fav do
                local text = data.fav[i]
                if text then
                    table.insert(allFavoriteData, {text_item = text})
                end
            end
        end
        
        if #allClipboardData > 0 then
            loadMoreClipboardData(true)
        end
    end)
end

-- ==================== ڈیٹا بیس آپریشنز ====================
function saveToDB(text, tableName)
    if not text or text == "" then return end
    task(function(dbPath, text, tableName)
        require "import"
        import "android.database.sqlite.SQLiteDatabase"
        import "android.content.ContentValues"
        local d = SQLiteDatabase.openOrCreateDatabase(dbPath, nil)
        d.delete(tableName, "content=?", {text})
        local values = ContentValues()
        values.put("content", text)
        d.insert(tableName, nil, values)
        d.close()
        return true
    end, dbFile, text, tableName, function()
        loadAllDataToCache()
    end)
end

function deleteFromDB(text, tableName)
    task(function(dbPath, text, tableName)
        require "import"
        import "android.database.sqlite.SQLiteDatabase"
        local d = SQLiteDatabase.openOrCreateDatabase(dbPath, nil)
        d.delete(tableName, "content=?", {text})
        d.close()
        return true
    end, dbFile, text, tableName, function()
        loadAllDataToCache()
    end)
end

-- ==================== سرچ فنکشن ====================
local function searchInCache(cache, keyword, adapter, isFavorite)
    adapter.clear()
    if keyword == nil or keyword == "" then
        if not isFavorite then
            if #allClipboardData > 0 then
                loadMoreClipboardData(true)
            end
        end
    else
        local searchKey = string.lower(keyword)
        local tempItems = {}
        local dataToSearch = isFavorite and allFavoriteData or allClipboardData
        
        for i = 1, #dataToSearch do
            local item = dataToSearch[i]
            if item and item.text_item and string.find(string.lower(item.text_item), searchKey, 1, true) then
                table.insert(tempItems, item)
            end
        end
        
        for i = 1, #tempItems do
            adapter.add(tempItems[i])
        end
    end
    adapter.notifyDataSetChanged()
end

-- ==================== یوزر پروفائل ڈائیلاگ ====================
local function showProfileDialog()
    if not ctx then return end
    
    -- پہلے چیک کریں کہ یوزر لاگ ان ہے یا نہیں
    local name, email = getUserInfo()
    
    if not name then
        -- لاگ ان نہیں، لاگ ان ڈائیلاگ دکھائیں
        showLoginDialog()
        return
    end
    
    -- لاگ ان ہے، پروفائل ڈائیلاگ دکھائیں
    local profileLayout = {
        LinearLayout,
        orientation = "vertical",
        padding = "20dp",
        layout_width = "match_parent",
        {
            TextView,
            text = "User Profile",
            textSize = "20sp",
            textColor = "#2196F3",
            gravity = "center",
            layout_marginBottom = "20dp"
        },
        {
            TextView,
            id = "profileName",
            text = "Name: " .. (name or "Unknown"),
            textSize = "16sp",
            textColor = "#212121",
            layout_marginBottom = "10dp",
            typeface = Typeface.DEFAULT_BOLD
        },
        {
            TextView,
            id = "profileEmail",
            text = "Email: " .. (email or "Not provided"),
            textSize = "14sp",
            layout_marginBottom = "20dp"
        },
        {
            Button,
            id = "btnLogout",
            text = "LOGOUT",
            layout_width = "match_parent",
            backgroundColor = "#F44336",
            textColor = "#FFFFFF",
            layout_marginBottom = "10dp"
        },
        {
            Button,
            id = "btnDeleteAccount",
            text = "DELETE ACCOUNT PERMANENTLY",
            layout_width = "match_parent",
            backgroundColor = "#000000",
            textColor = "#FFFFFF"
        },
        {
            Button,
            id = "btnProfileClose",
            text = "CLOSE",
            layout_width = "match_parent",
            backgroundColor = "#2196F3",
            textColor = "#FFFFFF",
            layout_marginTop = "10dp"
        }
    }
    
    local profileDialog = LuaDialog(ctx)
    profileDialog.setTitle("Profile Settings")
    profileDialog.setView(loadlayout(profileLayout))
    
    btnLogout.onClick = function()
        local builder = AlertDialog.Builder(ctx)
        builder.setTitle("Confirm Logout")
        builder.setMessage("Are you sure you want to logout?")
        builder.setPositiveButton("Yes", function()
            logout()
            profileDialog.dismiss()
        end)
        builder.setNegativeButton("No", nil)
        builder.show()
    end
    
    btnDeleteAccount.onClick = function()
        local builder = AlertDialog.Builder(ctx)
        builder.setTitle("Delete Account")
        builder.setMessage("This will permanently delete all your data. This action cannot be undone. Continue?")
        builder.setPositiveButton("DELETE", function()
            local d = SQLiteDatabase.openOrCreateDatabase(dbFile, nil)
            d.delete("user_info", nil, nil)
            d.delete("access_tokens", nil, nil)
            d.close()
            
            Toast.makeText(ctx, "Account deleted", Toast.LENGTH_SHORT).show()
            if btnUser then btnUser.setText("USER NAME") end
            profileDialog.dismiss()
        end)
        builder.setNegativeButton("Cancel", nil)
        builder.show()
    end
    
    btnProfileClose.onClick = function()
        profileDialog.dismiss()
    end
    
    profileDialog.show()
end

-- ==================== ایڈٹ ڈائیلاگ ====================
local function showEditDialog(itemText, position, isFavorite, adapter, listView, cache)
    if not ctx then return end
    
    local editLayout = {
        LinearLayout,
        orientation = "vertical",
        padding = "20dp",
        layout_width = "match_parent",
        {
            EditText,
            id = "etEdit",
            text = itemText,
            layout_width = "match_parent",
            layout_marginBottom = "15dp"
        },
        {
            LinearLayout,
            orientation = "horizontal",
            layout_width = "match_parent",
            gravity = "center",
            {
                Button,
                text = "CANCEL",
                id = "btnCancel",
                layout_weight = 1,
                layout_marginRight = "5dp",
                backgroundColor = "#9E9E9E",
                textColor = "#FFFFFF"
            },
            {
                Button,
                text = "OK",
                id = "btnOk",
                layout_weight = 1,
                layout_marginLeft = "5dp",
                backgroundColor = "#2196F3",
                textColor = "#FFFFFF"
            }
        }
    }
    
    local editDialog = LuaDialog(ctx)
    editDialog.setTitle("Edit")
    editDialog.setView(loadlayout(editLayout))
    
    btnCancel.onClick = function()
        editDialog.dismiss()
    end
    
    btnOk.onClick = function()
        local newText = etEdit.getText()
        if newText then
            newText = tostring(newText)
            if newText ~= "" and newText ~= itemText then
                local tableName = isFavorite and "favorite_history" or "clipboard_history"
                
                deleteFromDB(itemText, tableName)
                saveToDB(newText, tableName)
                
                if isFavorite then
                    for i = 1, #allFavoriteData do
                        if allFavoriteData[i] and allFavoriteData[i].text_item == itemText then
                            allFavoriteData[i].text_item = newText
                            break
                        end
                    end
                else
                    for i = 1, #allClipboardData do
                        if allClipboardData[i] and allClipboardData[i].text_item == itemText then
                            allClipboardData[i].text_item = newText
                            break
                        end
                    end
                end
                
                if not isFavorite then
                    if #allClipboardData > 0 then
                        loadMoreClipboardData(true)
                    end
                end
                
                if listView then listView.setSelection(0) end
            end
        end
        editDialog.dismiss()
    end
    
    editDialog.show()
end

-- ==================== مزید فیورٹ ڈیٹا لوڈ کریں ====================
local function loadMoreFavoriteData(adapter, reset)
    if reset then
        favCurrentOffset = 0
        adapter.clear()
    end
    
    local startIndex = favCurrentOffset + 1
    local endIndex = math.min(favCurrentOffset + ITEMS_PER_PAGE, #allFavoriteData)
    
    if startIndex <= endIndex then
        for i = startIndex, endIndex do
            if allFavoriteData[i] then
                adapter.add(allFavoriteData[i])
            end
        end
    end
    
    favCurrentOffset = endIndex
    local favHasMoreItems = (favCurrentOffset < #allFavoriteData)
    
    return favHasMoreItems
end

-- ==================== فیورٹ ڈائیلاگ ====================
local function showFavoritesDialog()
    if not ctx then return end
    
    local favDialog = LuaDialog(ctx)
    favDialog.setTitle("Favorites")
    
    local favLayout = {
        LinearLayout,
        orientation = "vertical",
        padding = "10dp",
        layout_width = "match_parent",
        layout_height = "match_parent",
        {
            EditText,
            id = "favEtSearch",
            hint = "Type to search...",
            layout_width = "match_parent",
            layout_height = "wrap_content",
            visibility = "gone",
            backgroundColor = "#FFFFFF",
            padding = "10dp",
            textSize = "16sp",
            singleLine = true
        },
        {
            Button,
            id = "favBtnKeyword",
            text = "ENTER KEYWORD",
            layout_width = "match_parent",
            layout_height = "wrap_content",
            layout_marginBottom = "5dp",
            backgroundColor = "#2196F3",
            textColor = "#FFFFFF",
            textSize = "16sp"
        },
        {
            ListView,
            id = "favLvClipboard",
            layout_width = "match_parent",
            layout_height = "0dp",
            layout_weight = 1,
            layout_marginTop = "5dp",
            layout_marginBottom = "5dp",
            dividerHeight = "1dp",
            backgroundColor = "#F5F5F5"
        },
        {
            Button,
            id = "favBtnLoadMore",
            text = "LOAD MORE ITEMS",
            layout_width = "match_parent",
            layout_height = "wrap_content",
            backgroundColor = "#4CAF50",
            textColor = "#FFFFFF",
            textSize = "14sp",
            visibility = "gone",
            layout_marginBottom = "5dp"
        },
        {
            Button,
            id = "favBtnSearchCancel",
            text = "CANCEL",
            layout_width = "match_parent",
            layout_height = "wrap_content",
            visibility = "gone",
            backgroundColor = "#F44336",
            textColor = "#FFFFFF",
            textSize = "14sp",
            layout_marginBottom = "5dp"
        },
        {
            LinearLayout,
            id = "favButtonsContainer",
            layout_width = "match_parent",
            layout_height = "wrap_content",
            orientation = "horizontal",
            gravity = "center",
            {
                Button,
                text = "MANAGE",
                id = "favBtnManage",
                layout_weight = 1,
                layout_height = "wrap_content",
                layout_marginRight = "2dp",
                backgroundColor = "#4CAF50",
                textColor = "#FFFFFF",
                textSize = "14sp"
            },
            {
                Button,
                text = "EXIT",
                id = "favBtnExit",
                layout_weight = 1,
                layout_height = "wrap_content",
                layout_marginLeft = "2dp",
                layout_marginRight = "2dp",
                backgroundColor = "#F44336",
                textColor = "#FFFFFF",
                textSize = "14sp"
            },
            {
                Button,
                text = "NEW",
                id = "favBtnNew",
                layout_weight = 1,
                layout_height = "wrap_content",
                layout_marginLeft = "2dp",
                backgroundColor = "#FF9800",
                textColor = "#FFFFFF",
                textSize = "14sp"
            }
        }
    }
    
    favDialog.setView(loadlayout(favLayout))
    
    local favAdapter = LuaAdapter(ctx, {}, item_layout)
    favLvClipboard.setAdapter(favAdapter)
    
    local function loadMoreFavorites(reset)
        if reset then
            favCurrentOffset = 0
            favAdapter.clear()
        end
        
        local startIndex = favCurrentOffset + 1
        local endIndex = math.min(favCurrentOffset + ITEMS_PER_PAGE, #allFavoriteData)
        
        if startIndex <= endIndex then
            for i = startIndex, endIndex do
                if allFavoriteData[i] then
                    favAdapter.add(allFavoriteData[i])
                end
            end
        end
        
        favCurrentOffset = endIndex
        local favHasMoreItems = (favCurrentOffset < #allFavoriteData)
        
        if favHasMoreItems then
            favBtnLoadMore.setVisibility(View.VISIBLE)
        else
            favBtnLoadMore.setVisibility(View.GONE)
        end
    end
    
    if allFavoriteData and #allFavoriteData > 0 then
        loadMoreFavorites(true)
    end
    
    favBtnLoadMore.onClick = function()
        loadMoreFavorites(false)
    end
    
    local favSearchHandler = Handler()
    local favSearchRunnable = nil
    
    favBtnKeyword.onClick = function()
        favBtnKeyword.setVisibility(8)
        favButtonsContainer.setVisibility(8)
        favEtSearch.setVisibility(0)
        favBtnSearchCancel.setVisibility(0)
        favBtnLoadMore.setVisibility(8)
        favEtSearch.requestFocus()
        
        local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
        imm.toggleSoftInput(InputMethodManager.SHOW_FORCED, 0)
    end
    
    favEtSearch.addTextChangedListener({
        onTextChanged = function(s)
            if favSearchRunnable then favSearchHandler.removeCallbacks(favSearchRunnable) end
            favSearchRunnable = Runnable({
                run = function()
                    searchInCache(allFavoriteData, tostring(s), favAdapter, true)
                end
            })
            favSearchHandler.postDelayed(favSearchRunnable, 1000)
        end
    })
    
    favBtnSearchCancel.onClick = function()
        favEtSearch.setVisibility(8)
        favBtnSearchCancel.setVisibility(8)
        favBtnKeyword.setVisibility(0)
        favButtonsContainer.setVisibility(0)
        favEtSearch.setText("")
        
        loadMoreFavorites(true)
        
        local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
        imm.hideSoftInputFromWindow(favEtSearch.getWindowToken(), 0)
    end
    
    favBtnManage.onClick = function()
        if #allFavoriteData == 0 then
            Toast.makeText(ctx, "Favorites list is empty", Toast.LENGTH_SHORT).show()
            return
        end
        
        local manageDialog = LuaDialog(ctx)
        manageDialog.setTitle("Manage Favorites")
        manageDialog.setMessage("Clear all favorites?")
        manageDialog.setPositiveButton("Clear All", function()
            task(function(dbPath)
                require "import"
                import "android.database.sqlite.SQLiteDatabase"
                local d = SQLiteDatabase.openOrCreateDatabase(dbPath, nil)
                d.delete("favorite_history", nil, nil)
                d.close()
                return true
            end, dbFile, function()
                loadAllDataToCache()
            end)
            
            Toast.makeText(ctx, "All favorites cleared", Toast.LENGTH_SHORT).show()
        end)
        manageDialog.setNeutralButton("Cancel", nil)
        manageDialog.show()
    end
    
    favBtnNew.onClick = function()
        local newLayout = {
            LinearLayout,
            orientation = "vertical",
            padding = "20dp",
            {
                EditText,
                id = "newFavEt",
                hint = "Enter new favorite...",
                layout_width = "match_parent"
            }
        }
        
        local newDialog = LuaDialog(ctx)
        newDialog.setTitle("Add New Favorite")
        newDialog.setView(loadlayout(newLayout))
        newDialog.setPositiveButton("Add", function()
            local newText = newFavEt.getText()
            if newText then
                newText = tostring(newText)
                if newText ~= "" then
                    saveToDB(newText, "favorite_history")
                    
                    local newItem = {text_item = newText}
                    table.insert(allFavoriteData, 1, newItem)
                    loadMoreFavorites(true)
                    
                    Toast.makeText(ctx, "Added to favorites", Toast.LENGTH_SHORT).show()
                end
            end
            newDialog.dismiss()
        end)
        newDialog.setNegativeButton("Cancel", nil)
        newDialog.show()
    end
    
    favBtnExit.onClick = function()
        favDialog.dismiss()
    end
    
    favLvClipboard.onItemClick = function(l, v, p, i)
        local item = favAdapter.getItem(p)
        if item and item.text_item then
            local text = tostring(item.text_item)
            local manager = ctx.getSystemService(Context.CLIPBOARD_SERVICE)
            manager.setPrimaryClip(ClipData.newPlainText("label", text))
            Toast.makeText(ctx, "Copied: " .. text, Toast.LENGTH_SHORT).show()
        end
    end
    
    favLvClipboard.setOnItemLongClickListener(AdapterView.OnItemLongClickListener({
        onItemLongClick = function(parent, view, position, id)
            local item = favAdapter.getItem(position)
            if not item or not item.text_item then return true end
            local text = tostring(item.text_item)
            
            local popup = ListPopupWindow(ctx)
            local options = {"Remove from favorites", "Edit", "Delete"}
            local adapter = ArrayAdapter(ctx, android.R.layout.simple_list_item_1, options)
            popup.setAdapter(adapter)
            popup.setAnchorView(view)
            popup.setWidth(400)
            popup.setHeight(300)
            popup.setModal(true)
            
            popup.setOnItemClickListener(AdapterView.OnItemClickListener({
                onItemClick = function(p, v, pos, id)
                    if pos == 0 then
                        deleteFromDB(text, "favorite_history")
                        
                        for i = 1, #allFavoriteData do
                            if allFavoriteData[i] and allFavoriteData[i].text_item == text then
                                table.remove(allFavoriteData, i)
                                break
                            end
                        end
                        
                        loadMoreFavorites(true)
                        
                    elseif pos == 1 then
                        showEditDialog(text, position, true, favAdapter, favLvClipboard, allFavoriteData)
                        
                    elseif pos == 2 then
                        local confirmDialog = LuaDialog(ctx)
                        confirmDialog.setTitle("Delete " .. text)
                        confirmDialog.setMessage("Delete this item?")
                        confirmDialog.setPositiveButton("DELETE", function()
                            deleteFromDB(text, "favorite_history")
                            
                            for i = 1, #allFavoriteData do
                                if allFavoriteData[i] and allFavoriteData[i].text_item == text then
                                    table.remove(allFavoriteData, i)
                                    break
                                end
                            end
                            
                            loadMoreFavorites(true)
                            
                            Toast.makeText(ctx, "Deleted", Toast.LENGTH_SHORT).show()
                        end)
                        confirmDialog.setNegativeButton("CANCEL", nil)
                        confirmDialog.show()
                    end
                    popup.dismiss()
                end
            }))
            
            popup.show()
            return true
        end
    }))
    
    favDialog.show()
end

-- ==================== ABOUT AND SUPPORT ڈائیلاگ ====================
local function showAboutDialog()
    if not ctx then return end
    
    local aboutLayout = {
        LinearLayout,
        orientation = "vertical",
        padding = "20dp",
        layout_width = "match_parent",
        {
            TextView,
            text = "My Clipboard Manager",
            textSize = "20sp",
            textColor = "#2196F3",
            layout_marginBottom = "10dp",
            gravity = "center"
        },
        {
            TextView,
            text = "Version 2.0 (with Google Drive Backup)",
            textSize = "14sp",
            layout_marginBottom = "20dp",
            gravity = "center"
        },
        {
            TextView,
            text = "Features:\n• Save clipboard history\n• Favorites\n• Search\n• Load More Items (1000 at a time)\n• Google Drive Backup",
            textSize = "14sp",
            layout_marginBottom = "20dp"
        },
        {
            Button,
            text = "CLOSE",
            layout_width = "match_parent",
            backgroundColor = "#2196F3",
            textColor = "#FFFFFF",
            onClick = function() aboutDialog.dismiss() end
        }
    }
    
    local aboutDialog = LuaDialog(ctx)
    aboutDialog.setTitle("About & Support")
    aboutDialog.setView(loadlayout(aboutLayout))
    aboutDialog.show()
end

-- ==================== بیک اپ ڈائیلاگ ====================
local function showBackupRestoreDialog()
    if not ctx then return end
    
    -- پہلے چیک کریں کہ یوزر لاگ ان ہے یا نہیں
    local name, email = getUserInfo()
    
    if not name then
        -- لاگ ان نہیں، لاگ ان ڈائیلاگ دکھائیں
        showLoginDialog()
        return
    end
    
    -- لاگ ان ہے، بیک اپ ڈائیلاگ دکھائیں
    local backupLayout = {
        LinearLayout,
        orientation = "vertical",
        padding = "20dp",
        layout_width = "match_parent",
        {
            TextView,
            text = "Google Drive Backup",
            textSize = "18sp",
            textColor = "#4CAF50",
            gravity = "center",
            layout_marginBottom = "20dp"
        },
        {
            TextView,
            id = "backupUserInfo",
            text = "Connected as: " .. (name or "User"),
            textSize = "14sp",
            gravity = "center",
            layout_marginBottom = "20dp"
        },
        {
            Button,
            id = "btnBackup",
            text = "CREATE BACKUP",
            layout_width = "match_parent",
            backgroundColor = "#4CAF50",
            textColor = "#FFFFFF",
            layout_marginBottom = "10dp"
        },
        {
            Button,
            id = "btnRestore",
            text = "RESTORE FROM BACKUP",
            layout_width = "match_parent",
            backgroundColor = "#FF9800",
            textColor = "#FFFFFF",
            layout_marginBottom = "10dp"
        },
        {
            Button,
            id = "btnBackupLogout",
            text = "LOGOUT",
            layout_width = "match_parent",
            backgroundColor = "#F44336",
            textColor = "#FFFFFF",
            layout_marginBottom = "10dp"
        },
        {
            Button,
            text = "CANCEL",
            layout_width = "match_parent",
            backgroundColor = "#2196F3",
            textColor = "#FFFFFF",
            onClick = function() backupDialog.dismiss() end
        }
    }
    
    local backupDialog = LuaDialog(ctx)
    backupDialog.setTitle("Backup Manager")
    backupDialog.setView(loadlayout(backupLayout))
    
    if email then
        backupUserInfo.setText("Connected as: " .. name .. "\n" .. email)
    end
    
    btnBackup.onClick = function()
        Toast.makeText(ctx, "Backup feature coming soon!", Toast.LENGTH_SHORT).show()
    end
    
    btnRestore.onClick = function()
        Toast.makeText(ctx, "Restore feature coming soon!", Toast.LENGTH_SHORT).show()
    end
    
    btnBackupLogout.onClick = function()
        local builder = AlertDialog.Builder(ctx)
        builder.setTitle("Confirm Logout")
        builder.setMessage("Are you sure you want to logout from Google Drive?")
        builder.setPositiveButton("Yes", function()
            logout()
            backupDialog.dismiss()
        end)
        builder.setNegativeButton("No", nil)
        builder.show()
    end
    
    backupDialog.show()
end

-- ==================== مین سرچ ڈیباؤنس ====================
local mainSearchHandler = Handler()
local mainSearchRunnable = nil

-- ==================== یوزر بٹن اپڈیٹ ====================
local function updateUserButton()
    local name, email = getUserInfo()
    if name and btnUser then
        btnUser.setText(name)
    elseif btnUser then
        btnUser.setText("USER NAME")
    end
end

-- بٹنز کے onClick ایونٹس
btnUser.onClick = function() showProfileDialog() end
btnAbout.onClick = function() showAboutDialog() end
btnBackupRestore.onClick = function() showBackupRestoreDialog() end
btnFav.onClick = function() showFavoritesDialog() end

dlg.show()
loadAllDataToCache()
updateUserButton()

btnKeyword.onClick = function()
    btnKeyword.setVisibility(8)
    mainButtonsContainer.setVisibility(8)
    mainEtSearch.setVisibility(0)
    mainBtnSearchCancel.setVisibility(0)
    btnLoadMore.setVisibility(8)
    mainEtSearch.requestFocus()
    local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
    imm.toggleSoftInput(InputMethodManager.SHOW_FORCED, 0)
end

mainEtSearch.addTextChangedListener({
    onTextChanged = function(s)
        if mainSearchRunnable then mainSearchHandler.removeCallbacks(mainSearchRunnable) end
        mainSearchRunnable = Runnable({
            run = function()
                searchInCache(allClipboardData, tostring(s), mainAdapter, false)
            end
        })
        mainSearchHandler.postDelayed(mainSearchRunnable, 1000)
    end
})

mainBtnSearchCancel.onClick = function()
    mainEtSearch.setVisibility(8)
    mainBtnSearchCancel.setVisibility(8)
    btnKeyword.setVisibility(0)
    mainButtonsContainer.setVisibility(0)
    mainEtSearch.setText("")
    
    if #allClipboardData > 0 then
        loadMoreClipboardData(true)
    end
    
    local imm = ctx.getSystemService(Context.INPUT_METHOD_SERVICE)
    imm.hideSoftInputFromWindow(mainEtSearch.getWindowToken(), 0)
end

btnLoadMore.onClick = function()
    loadMoreClipboardData(false)
end

-- مانیٹرنگ سسٹم
local lastCheckedText = getClipText() or ""
local isRunning = true
local handler = Handler(Looper.getMainLooper())

local function monitor()
    if not isRunning then return end
    local current = getClipText()
    
    if current and current ~= "" and current ~= lastCheckedText then
        lastCheckedText = current
        saveToDB(current, "clipboard_history")
    end
    handler.postDelayed(Runnable({run = monitor}), 500)
end
monitor()

btnExit.onClick = function()
    isRunning = false
    handler.removeCallbacksAndMessages(nil)
    dlg.dismiss()
end

lvClipboard.onItemClick = function(l, v, p, i)
    local item = mainAdapter.getItem(p)
    if item and item.text_item then
        local text = tostring(item.text_item)
        local manager = ctx.getSystemService(Context.CLIPBOARD_SERVICE)
        manager.setPrimaryClip(ClipData.newPlainText("label", text))
        lastCheckedText = text
        Toast.makeText(ctx, "Copied: " .. text, Toast.LENGTH_SHORT).show()
    end
end

lvClipboard.setOnItemLongClickListener(AdapterView.OnItemLongClickListener({
    onItemLongClick = function(parent, view, position, id)
        local item = mainAdapter.getItem(position)
        if not item or not item.text_item then return true end
        local text = tostring(item.text_item)
        
        local popup = ListPopupWindow(ctx)
        local options = {"Add to favorites", "Edit", "Delete"}
        local adapter = ArrayAdapter(ctx, android.R.layout.simple_list_item_1, options)
        popup.setAdapter(adapter)
        popup.setAnchorView(view)
        popup.setWidth(400)
        popup.setHeight(300)
        popup.setModal(true)
        
        popup.setOnItemClickListener(AdapterView.OnItemClickListener({
            onItemClick = function(p, v, pos, id)
                if pos == 0 then
                    saveToDB(text, "favorite_history")
                    
                    local newItem = {text_item = text}
                    
                    for i = 1, #allFavoriteData do
                        if allFavoriteData[i] and allFavoriteData[i].text_item == text then
                            table.remove(allFavoriteData, i)
                            break
                        end
                    end
                    
                    table.insert(allFavoriteData, 1, newItem)
                    
                    Toast.makeText(ctx, "Added to favorites", Toast.LENGTH_SHORT).show()
                    
                elseif pos == 1 then
                    showEditDialog(text, position, false, mainAdapter, lvClipboard, allClipboardData)
                    
                elseif pos == 2 then
                    local confirmDialog = LuaDialog(ctx)
                    confirmDialog.setTitle("Delete " .. text)
                    confirmDialog.setMessage("Delete this item?")
                    confirmDialog.setPositiveButton("DELETE", function()
                        deleteFromDB(text, "clipboard_history")
                        
                        for i = 1, #allClipboardData do
                            if allClipboardData[i] and allClipboardData[i].text_item == text then
                                table.remove(allClipboardData, i)
                                break
                            end
                        end
                        
                        if #allClipboardData > 0 then
                            loadMoreClipboardData(true)
                        end
                        
                        Toast.makeText(ctx, "Deleted", Toast.LENGTH_SHORT).show()
                    end)
                    confirmDialog.setNegativeButton("CANCEL", nil)
                    confirmDialog.show()
                end
                popup.dismiss()
            end
        }))
        
        popup.show()
        return true
    end
}))