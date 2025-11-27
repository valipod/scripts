libraries="Copii - Română	3\nCopii - Deutsch	24\nCopii - English	8\nCopii - Serii	1\nDocumentare - Filme	22\nDocumentare - Serii	6\nFilme	2\nMy Movies	7\nRomânești	25\nSeriale	4\nTeatru	11\nMusic	20\nSport	21\n14+	32\nDe dat - Seriale 34\nParenting	35\nThe Flexitarian Way	36\n8+ (Română)	37\nVlad	42"
echo -e $libraries
echo
echo 'update metadata_items set added_at = originally_available_at where library_section_id="2";'
echo 'update metadata_items set added_at = originally_available_at where title="In Bruges";'
/var/packages/PlexMediaServer/target/Plex\ Media\ Server --sqlite /volume1/PlexMediaServer/AppData/Plex\ Media\ Server/Plug-in\ Support/Databases/com.plexapp.plugins.library.db

