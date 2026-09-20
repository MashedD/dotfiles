#include <gtk/gtk.h>

int main(int argc, char **argv) {
    gtk_init(&argc, &argv);
    GtkIconTheme *theme = gtk_icon_theme_get_default();
    GtkIconInfo *info = gtk_icon_theme_lookup_icon(theme, "vax-tux-start", 32, 0);
    if (info == NULL) {
        return 1;
    }
    g_print("%s\n", gtk_icon_info_get_filename(info));
    return 0;
}
