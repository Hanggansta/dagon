/*
Copyright (c) 2014-2018 Timur Gafarov

Boost Software License - Version 1.0 - August 17th, 2003

Permission is hereby granted, free of charge, to any person or organization
obtaining a copy of the software and accompanying documentation covered by
this license (the "Software") to use, reproduce, display, distribute,
execute, and transmit the Software, and to prepare derivative works of the
Software, and to permit third-parties to whom the Software is furnished to
do so, all subject to the following:

The copyright notices in the Software and this entire statement, including
the above license grant, this restriction and the following disclaimer,
must be included in all copies of the Software, in whole or in part, and
all derivative works of the Software, unless such copies or derivative
works are solely in the form of machine-executable object code generated by
a source language processor.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
*/

module dmech.jss;

import dlib.math.vector;

struct JohnsonSimplexSolver
{
    void initialize()
    {
        foreach(ref v; supportPointsOnA)
            v = Vector3f(0, 0, 0);

        foreach(ref v; supportPointsOnB)
            v = Vector3f(0, 0, 0);

        foreach(ref e; edges)
        foreach(ref v; e)
            v = Vector3f(0, 0, 0);

        foreach(ref row; determinants)
        foreach(ref v; row)
            v = 0.0f;
    }

    void calcClosestPoint(out Vector3f v)
    {
        float maxVertexSqrd = 0;
        float deltaX = 0;

        Vector3f closestPoint = Vector3f(0, 0, 0);

        for (byte i = 0; i < 4; ++i)
        {
            if (isReducedSimplexPoint(i))
            {
                float determinant = determinants[XBits][i];
                Vector3f point = edges[i][i];

                assert(determinant > 0, "Negative or zero determinant found");

                closestPoint += point * determinant;
                deltaX += determinant;

                if (determinants[0][i] > maxVertexSqrd)
                {
                    maxVertexSqrd = determinants[0][i];
                    maxVertexIndex = i;
                }
            }
        }
    
        v = closestPoint / deltaX;
    }

    void calcClosestPoint(byte set, out Vector3f v)
    {
        float deltaX = 0;

        Vector3f closestPoint = Vector3f(0, 0, 0);

        for (byte i = 0; i < 4; ++i)
        {
            if (set & (1 << i))
            {
                float determinant = determinants[set][i];
                Vector3f point = edges[i][i];

                assert(determinant > 0, "Negative or zero determinant found");

                closestPoint += point * determinant;

                deltaX += determinant;
            }
        }

        v = closestPoint / deltaX;
    }

    void backupCalcClosestPoint(out Vector3f v)
    {
        // We don't need to update maxVertexIndex because this method is called when the algorithm terminates
        float closestPointSqrd = float.max;

        for (byte subset = YBits; subset > 0; --subset)
        {
            if (isSubsetOrEqualTo(YBits, subset) && isProperSet(subset))
            {
                Vector3f point;

                calcClosestPoint(subset, point);

                float pointSqrd = dot(point, point);
                if (pointSqrd < closestPointSqrd)
                {
                    XBits = subset;

                    closestPointSqrd = pointSqrd;
                    v = point;
                }
            }
        }
    }

    void calcClosestPoints(out Vector3f pClosestPointOnA, out Vector3f pClosestPointOnB)
    {
        float deltaX = 0;

        Vector3f p = Vector3f(0,0,0);
        Vector3f q = Vector3f(0,0,0);

        for (byte i = 0; i < 4; ++i)
        {
            if (isReducedSimplexPoint(i))
            {
                float determinant = determinants[XBits][i];

                assert(determinant > 0, "Negative or zero determinant found");

                p += supportPointsOnA[i] * determinant;
                q += supportPointsOnB[i] * determinant;

                deltaX += determinant;
            }
        }

        pClosestPointOnA = p / deltaX;
        pClosestPointOnB = q / deltaX;
    }

    bool reduceSimplex()
    {
        for (byte subset = YBits; subset > 0; --subset)
        {
            if ((subset & (1 << lastVertexIndex)) && isSubsetOrEqualTo(YBits, subset) && isValidSet(subset))
            {
                XBits = subset;
                return true;
            }
        }

        // failed to reduce simplex
        return false;
    }


    void addPoint(Vector3f point)
    {
        // Find a free slot for new point
        byte freeSlot = findFreeSlot();
        if (freeSlot == 4)
        {
            // Simplex is full
            return;
        }

        lastVertexIndex = freeSlot;
        YBits = cast(byte)(XBits | (1 << lastVertexIndex));
        edges[lastVertexIndex][lastVertexIndex] = point;

        // Update edges and determinants for new point
        updateEdges(lastVertexIndex);
        updateDeterminants(lastVertexIndex);

        // Update max vertex
        float pointSqrd = dot(point, point);
        if (pointSqrd > getMaxVertexSqrd())
            maxVertexIndex = lastVertexIndex;

        determinants[0][lastVertexIndex] = pointSqrd;
    }

    void addPoint(Vector3f point, Vector3f supportOnA, Vector3f supportOnB)
    {
        // Find a free slot for new point
        byte freeSlot = findFreeSlot();
        if (freeSlot == 4)
        {
            // Simplex is full
            return;
        }

        lastVertexIndex = freeSlot;
        YBits = cast(byte)(XBits | (1 << lastVertexIndex));

        edges[lastVertexIndex][lastVertexIndex] = point;
        supportPointsOnA[lastVertexIndex] = supportOnA;
        supportPointsOnB[lastVertexIndex] = supportOnB;

        // Update edges and determinants for new point
        updateEdges(lastVertexIndex);
        updateDeterminants(lastVertexIndex);

        // Update max vertex
        float pointSqrd = dot(point, point);
        if (pointSqrd > getMaxVertexSqrd())
            maxVertexIndex = lastVertexIndex;

        determinants[0][lastVertexIndex] = pointSqrd;
    }

    void removeAllPoints()
    {
        XBits = 0;
        YBits = 0;

        maxVertexIndex = 3;
        lastVertexIndex = 3;
    }

    void loadSimplex(byte simplexBits, Vector3f[] simplexPoints)
    {
        // Reset simplex
        removeAllPoints();

        float maxPointSqrd = -float.max;

        // Add new vertices
        for (byte i = 0; i < 4; ++i)
        {
            if (simplexBits & (1 << i))
            {
                edges[i][i] = simplexPoints[i];
                determinants[0][i] = dot(edges[i][i], edges[i][i]);

                if (determinants[0][i] > maxPointSqrd)
                {
                    maxPointSqrd = determinants[0][i];
                    maxVertexIndex = i;
                }

                lastVertexIndex = i;
            }
        }
  
        assert(maxVertexIndex <= 3, "Invalid max vertex index");

        XBits = simplexBits;
        YBits = simplexBits;

        // Calculate new edges based on new vertices
        for (byte i = 0; i < 4; ++i)
        {
            if (simplexBits & (1 << i))
                updateEdges(i);
        }

        // Calculate new determinants based on new vertices
        for (byte i = 0; i < 4; ++i)
        {
            if (simplexBits & (1 << i))
                updateDeterminants(i);
        }
    }

    void loadSimplex(byte simplexBits, Vector3f[] simplexPoints, Vector3f[] supportOnA, Vector3f[] supportOnB)
    {
        loadSimplex(simplexBits, simplexPoints);

        for (byte i = 0; i < 4; ++i)
        {
            if (simplexBits & (1 << i))
            {
                supportPointsOnA[i] = supportOnA[i];
                supportPointsOnB[i] = supportOnB[i];
            }
        }
    }

    bool isReducedSimplexPoint(byte index)
    {
        assert(index < 4, "Invalid index");
        return (XBits & (1 << index)) > 0;
    }

    bool isReducedSimplexPoint(Vector3f point)
    {
        for (byte i = 0; i < 4; ++i)
        {
            if (isReducedSimplexPoint(i) && point == getPoint(i))
                return true;
        }

        return false;
    }

    bool isSimplexPoint(byte index)
    {
        assert(index < 4, "Invalid index");
        return (YBits & (1 << index)) > 0;
    }

    bool isSimplexPoint(Vector3f point)
    {
        for (byte i = 0; i < 4; ++i)
        {
            if (isSimplexPoint(i) && point == getPoint(i))
                return true;
        }

        return false;
    }

    Vector3f getPoint(byte index)
    {
        assert(index < 4, "Invalid index");
        return edges[index][index];
    }

    void setPoint(byte index, Vector3f point)
    {
        assert(index < 4, "Invalid index");
        edges[index][index] = point;
    }

    void setPoint(byte index, Vector3f point, Vector3f supportPointOnA, Vector3f supportPointOnB)
    {
        assert(index < 4, "Invalid index!");
        edges[index][index] = point;
        supportPointsOnA[index] = supportPointOnA;
        supportPointsOnB[index] = supportPointOnB;
    }

    byte getSimplex(Vector3f[] simplexPoints)
    {
        assert(simplexPoints.length >= 4, "Input array length must be greater or equal to 4");

        byte nbPoints = 0;

        for (byte i = 0; i < 4; ++i)
        {
            if (isReducedSimplexPoint(i))
            {
                simplexPoints[nbPoints] = getPoint(i);
                ++nbPoints;
            }
        }

        return nbPoints;
    }

    byte getSimplex(float[] simplexPoints)
    {
        assert(simplexPoints.length >= 12, "Input array length must be greater or equal to 12");

        byte nbPoints = 0;

        for (byte i = 0; i < 4; ++i)
        {
            if (isReducedSimplexPoint(i))
            {
                Vector3f point = getPoint(i);
                simplexPoints[nbPoints * 3]     = point.x;
                simplexPoints[nbPoints * 3 + 1] = point.y;
                simplexPoints[nbPoints * 3 + 2] = point.z;

                ++nbPoints;
            }
        }

       return nbPoints;
    }

    byte getSupportPointsOnA(Vector3f[] worldSupportPointsOnA)
    {
        assert(supportPointsOnA.length >= 4, "Input array length must be greater or equal to 4");

        byte nbPoints = 0;

        for (byte i = 0; i < 4; ++i)
        {
            if (isReducedSimplexPoint(i))
            {
                supportPointsOnA[nbPoints] = worldSupportPointsOnA[i];
                ++nbPoints;
            }
        }

        return nbPoints;
    }

    byte getSupportPointsOnB(Vector3f[] worldSupportPointsOnB)
    {
        assert(supportPointsOnB.length >= 4, "Input array length must be greater or equal to 4");

        byte nbPoints = 0;

        for (byte i = 0; i < 4; ++i)
        {
            if (isReducedSimplexPoint(i))
            {
                supportPointsOnB[nbPoints] = worldSupportPointsOnB[i];
                ++nbPoints;
            }
        }

        return nbPoints;
    }

    Vector3f getSupportPointOnA(byte index)
    {
        assert(index < 4, "Invalid index");
        return supportPointsOnA[index];
    }

    Vector3f getSupportPointOnB(byte index)
    {
        assert(index < 4, "Invalid index");
        return supportPointsOnB[index];
    }

    bool isFullSimplex()
    {
        return (XBits == 0xf);
    }

    bool isEmptySimplex()
    {
        return (XBits == 0);
    }

    void setMaxVertexSqrd(float maxVertexSqrd)
    {
        determinants[0][maxVertexIndex] = maxVertexSqrd;
    }

    float getMaxVertexSqrd()
    {
        return determinants[0][maxVertexIndex];
    }

    void updateMaxVertex()
    {
        float maxVertexSqrd = -float.max;

        for (byte i = 0; i < 4; ++i)
        {
            if (isSimplexPoint(i))
            {
                float pointSqrd = dot(edges[i][i], edges[i][i]);

                if (pointSqrd > maxVertexSqrd)
                {
                    maxVertexSqrd = pointSqrd;
                    maxVertexIndex = i;
                }
            }
        }

        determinants[0][maxVertexIndex] = maxVertexSqrd;
    }

    bool isSubsetOrEqualTo(byte set, byte subset)
    {
        return ((set & subset) == subset);
    }

    bool isValidSet(byte set)
    {
        for (byte i = 0; i < 4; ++i)
        {
            if (isSimplexPoint(i))
            {
                if (set & (1 << i))
                {
                    // i-th point does belong to set
                    if (determinants[set][i] <= 0)
                        return false;
                }
                else
                {
                    // i-th point does not belong to set
                    if (determinants[set | (1 << i)][i] > 0)
                        return false;
                }
            }
        }

        return true;
    }

    bool isProperSet(byte set)
    {
        for (byte i = 0; i < 4; ++i)
        {
            if ((set & (1 << i)) && determinants[set][i] <= 0)
                return false;
        }

        return true;
    }

    byte findFreeSlot()
    {
        for (byte i = 0; i < 4; ++i)
        {
            if (!isReducedSimplexPoint(i))
                return i;
        }

        // Invalid slot
        return 4;
    }

    void updateEdges(byte index)
    {
        assert(index < 4, "Invalid index");

        for (byte i = 0; i < 4; ++i)
        {
            if ((i != index) && isSimplexPoint(i))
            {
                edges[index][i] =  edges[index][index] - edges[i][i];
                edges[i][index] = -edges[index][i];
            }
        }
    }

    void updateDeterminants(byte index)
    {
        assert(index < 4, "Invalid index!");

        byte indexBit = cast(byte)(1 << index);
        determinants[indexBit][index] = 1;

        // Update determinants for all subsets that contain a "valid" point at index

        for (byte i = 0; i < 4; ++i)
        {
            if ((i != index) && isReducedSimplexPoint(i))
            {
                // calculate all determinants for subsets of combinations of 2 points including point at index
                byte subset2 = cast(byte)((1 << i) | indexBit);
                determinants[subset2][i] = dot(edges[index][i], getPoint(index));
                determinants[subset2][index] = dot(edges[i][index], getPoint(i));

                for (byte j = 0; j < i; ++j)
                {
                    if ((j != index) && isReducedSimplexPoint(j))
                    {
                        // calculate all determinants for subsets of combinations of 3 points including point at index
                        byte subset3 = cast(byte)(subset2 | (1 << j));

                        determinants[subset3][j] = 
                            dot(edges[i][j], getPoint(i)) * determinants[subset2][i] +
                            dot(edges[i][j], getPoint(index)) * determinants[subset2][index];

                        determinants[subset3][i] = 
                            dot(edges[j][i], getPoint(j)) * determinants[(1 << j) | indexBit][j] +
                            dot(edges[j][i], getPoint(index)) * determinants[(1 << j) | indexBit][index];

                        determinants[subset3][index] = 
                            dot(edges[j][index], getPoint(i)) * determinants[(1 << i) | (1 << j)][i] +
                            dot(edges[j][index], getPoint(j)) * determinants[(1 << i) | (1 << j)][j];
                    }
                }
            }
        }
    
        if (YBits == 0xf)
        {
            // compute determinants for full simplex

            determinants[YBits][0] = 
                dot(edges[1][0], getPoint(1)) * determinants[0xe][1] +
                dot(edges[1][0], getPoint(2)) * determinants[0xe][2] +
                dot(edges[1][0], getPoint(3)) * determinants[0xe][3];

            determinants[YBits][1] =
                dot(edges[0][1], getPoint(0)) * determinants[0xd][0] + 
                dot(edges[0][1], getPoint(2)) * determinants[0xd][2] +
                dot(edges[0][1], getPoint(3)) * determinants[0xd][3];

            determinants[YBits][2] = 
                dot(edges[0][2], getPoint(0)) * determinants[0xb][0] +
                dot(edges[0][2], getPoint(1)) * determinants[0xb][1] +
                dot(edges[0][2], getPoint(3)) * determinants[0xb][3];

            determinants[YBits][3] = 
                dot(edges[0][3], getPoint(0)) * determinants[0x7][0] +
                dot(edges[0][3], getPoint(1)) * determinants[0x7][1] +
                dot(edges[0][3], getPoint(2)) * determinants[0x7][2];
        }
    }

    // Reduced simplex bits.
    byte XBits = 0;

    // Y = Wk + wk
    byte YBits = 0;

    // Max vertex index
    byte maxVertexIndex = 3;

    // Last vertex index
    byte lastVertexIndex = 3;

    // Support points on shape A
    Vector3f[4] supportPointsOnA;

    // Support points on shape B
    Vector3f[4] supportPointsOnB;

    // Cached edges. The diagonal does not hold a subtraction, it holds all four simplex points instead
    Vector3f[4][4] edges;

    // Cached determinants. This cache supports any combination of simplex's 4 points.
    // The first column stores the squared length for each point
    float[4][16] determinants;
}

