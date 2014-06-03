/*
 *  Copyright (c) 2010 Cyrille Berger <cberger@cberger.net>
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 51 Franklin Street, Fifth Floor,
 * Boston, MA 02110-1301, USA.
 */

#include "exr_import.h"

#include <kpluginfactory.h>

#include <KoFilterChain.h>
#include <KoFilterManager.h>

#include <kis_doc2.h>
#include <kis_image.h>

#include "exr_converter.h"

K_PLUGIN_FACTORY(ImportFactory, registerPlugin<exrImport>();)
K_EXPORT_PLUGIN(ImportFactory("calligrafilters"))

exrImport::exrImport(QObject *parent, const QVariantList &) : KoFilter(parent)
{
}

exrImport::~exrImport()
{
}

KoFilter::ConversionStatus exrImport::convert(const QByteArray&, const QByteArray& to)
{
    dbgFile << "Importing using EXRImport!";

    if (to != "application/x-krita")
        return KoFilter::BadMimeType;

    KisDoc2 * doc = dynamic_cast<KisDoc2*>(m_chain->outputDocument());

    if (!doc)
        return KoFilter::NoDocumentCreated;

    QString filename = m_chain -> inputFile();

    doc->prepareForImport();

    if (!filename.isEmpty()) {

        KUrl url(filename);

        if (url.isEmpty())
            return KoFilter::FileNotFound;

        exrConverter ib(doc, !m_chain->manager()->getBatchMode());


        switch (ib.buildImage(url)) {
        case KisImageBuilder_RESULT_UNSUPPORTED:
            doc->setErrorMessage(i18n("Krita does support this type of EXR file."));
            return KoFilter::NotImplemented;

        case KisImageBuilder_RESULT_INVALID_ARG:
            doc->setErrorMessage(i18n("This is not an EXR file."));
            return KoFilter::BadMimeType;

        case KisImageBuilder_RESULT_NO_URI:
        case KisImageBuilder_RESULT_NOT_LOCAL:
            doc->setErrorMessage(i18n("The EXR file does not exist."));
            return KoFilter::FileNotFound;

        case KisImageBuilder_RESULT_BAD_FETCH:
        case KisImageBuilder_RESULT_EMPTY:
            doc->setErrorMessage(i18n("The EXR is corrupted."));
            return KoFilter::ParsingError;

        case KisImageBuilder_RESULT_FAILURE:
            doc->setErrorMessage(i18n("Krita could not create a new image."));
            return KoFilter::InternalError;

        case KisImageBuilder_RESULT_OK:
            Q_ASSERT(ib.image());
            doc -> setCurrentImage(ib.image());
            return KoFilter::OK;
        default:
            break;
        }

    }
    return KoFilter::StorageCreationError;
}

#include <exr_import.moc>

