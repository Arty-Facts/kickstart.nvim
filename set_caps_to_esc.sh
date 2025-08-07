# Get current options
CURRENT_OPTIONS=$(gsettings get org.gnome.desktop.input-sources xkb-options)

# Add 'caps:escape' if it's not already there
if [[ ! "$CURRENT_OPTIONS" =~ "caps:escape" ]]; then
    gsettings set org.gnome.desktop.input-sources xkb-options "['caps:escape']" 
    echo "Caps Lock remapped to Escape."
else
    echo "Caps Lock is already remapped to Escape."
fi
