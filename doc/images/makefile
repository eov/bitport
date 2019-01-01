sources = wallet-in-luks.tex wallet-backup.tex

products = wallet-in-luks.pdf wallet-in-luks.png wallet-in-luks-1.png \
	wallet-backup.pdf wallet-backup.png wallet-backup-1.png

all: $(products)

wallet-in-luks.pdf : wallet-in-luks.tex
	pdflatex wallet-in-luks.tex
wallet-backup.pdf : wallet-backup.tex
	pdflatex wallet-backup.tex

wallet-in-luks.png : wallet-in-luks.pdf
	/usr/bin/convert -density 125 -transparent white wallet-in-luks.pdf wallet-in-luks.png
wallet-backup.png : wallet-backup.pdf
	/usr/bin/convert -density 125 -transparent white wallet-backup.pdf wallet-backup.png

wallet-in-luks-1.png : wallet-in-luks.png
	/usr/bin/convert wallet-in-luks.png -crop 580x500+80+70 wallet-in-luks-1.png
wallet-backup-1.png : wallet-backup.png
	/usr/bin/convert wallet-backup.png -crop 750x830+80+95 wallet-backup-1.png

#wallet-in-luks.png : wallet-in-luks.pdf
#	/usr/bin/convert -density 150 -transparent white wallet-in-luks.pdf wallet-in-luks.png
#wallet-backup.png : wallet-backup.pdf
#	/usr/bin/convert -density 150 -transparent white wallet-backup.pdf wallet-backup.png
#
#wallet-in-luks-1.png : wallet-in-luks.png
#	/usr/bin/convert wallet-in-luks.png -crop 640x596+125+10 wallet-in-luks-1.png
#wallet-backup-1.png : wallet-backup.png
#	/usr/bin/convert wallet-backup.png -crop 850x996+135+115 wallet-backup-1.png


.PHONY : clean
clean :
	rm $(products)
