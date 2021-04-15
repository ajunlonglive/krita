/*
 *  SPDX-FileCopyrightText: 2015 Dmitry Kazakov <dimula73@gmail.com>
 *
 *  SPDX-License-Identifier: GPL-2.0-or-later
 */

#ifndef __KIS_LS_UTILS_H
#define __KIS_LS_UTILS_H

#include "kis_types.h"
#include "kritaimage_export.h"

#include "kis_lod_transform.h"
#include <KoPattern.h>

struct psd_layer_effects_context;
class psd_layer_effects_shadow_base;
struct psd_layer_effects_overlay_base;
class KisLayerStyleFilterEnvironment;

class KisMultipleProjection;
class KisCachedSelection;


namespace KisLsUtils
{

    QRect growSelectionUniform(KisPixelSelectionSP selection, int growSize, const QRect &applyRect);

    KRITAIMAGE_EXPORT void selectionFromAlphaChannel(KisPaintDeviceSP srcDevice,
                                                        KisSelectionSP dstSelection,
                                                        const QRect &srcRect);

    void findEdge(KisPixelSelectionSP selection, const QRect &applyRect, const bool edgeHidden);
    QRect growRectFromRadius(const QRect &rc, int radius);
    void applyGaussianWithTransaction(KisPixelSelectionSP selection,
                                      const QRect &applyRect,
                                      qreal radius);

    static const int FULL_PERCENT_RANGE = 100;
    void adjustRange(KisPixelSelectionSP selection, const QRect &applyRect, const int range);

    void applyContourCorrection(KisPixelSelectionSP selection,
                                const QRect &applyRect,
                                const quint8 *lookup_table,
                                bool antiAliased,
                                bool edgeHidden);

    extern const int noiseNeedBorder;

    void applyNoise(KisPixelSelectionSP selection,
                    const QRect &applyRect,
                    int noise,
                    const psd_layer_effects_context *context,
                    KisLayerStyleFilterEnvironment *env);

    void knockOutSelection(KisPixelSelectionSP selection,
                           KisPixelSelectionSP knockOutSelection,
                           const QRect &srcRect,
                           const QRect &dstRect,
                           const QRect &totalNeedRect,
                           const bool knockOutInverted);

    void fillPattern(KisPaintDeviceSP fillDevice,
                     const QRect &applyRect,
                     KisLayerStyleFilterEnvironment *env,
                     int scale,
                     KoPatternSP pattern,
                     int horizontalPhase,
                     int verticalPhase,
                     bool alignWithLayer);

    void fillOverlayDevice(KisPaintDeviceSP fillDevice,
                           const QRect &applyRect,
                           const psd_layer_effects_overlay_base *config,
                           KisResourcesInterfaceSP resourcesInterface,
                           KisLayerStyleFilterEnvironment *env);

    void applyFinalSelection(const QString &projectionId,
                             KisSelectionSP baseSelection,
                             KisPaintDeviceSP srcDevice,
                             KisMultipleProjection *dst,
                             const QRect &srcRect,
                             const QRect &dstRect,
                             const psd_layer_effects_context *context,
                             const psd_layer_effects_shadow_base *config, KisResourcesInterfaceSP resourcesInterface,
                             const KisLayerStyleFilterEnvironment *env);

    bool checkEffectEnabled(const psd_layer_effects_shadow_base *config, KisMultipleProjection *dst);

    template<class ConfigStruct>
    struct LodWrapper
    {
        LodWrapper(int lod,
                   const ConfigStruct *srcStruct)

            {
                if (lod > 0) {
                    storage.reset(new ConfigStruct(*srcStruct));

                    const qreal lodScale = KisLodTransform::lodToScale(lod);
                    storage->scaleLinearSizes(lodScale);

                    config = storage.data();
                } else {
                    config = srcStruct;
                }
            }

        const ConfigStruct *config;

    private:
        QScopedPointer<ConfigStruct> storage;
    };

}

#endif /* __KIS_LS_UTILS_H */
